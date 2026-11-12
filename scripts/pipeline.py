#!/usr/bin/env python3
'Download or copy an app, decrypt its IPA, and verify the result.'
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time
import uuid
import zipfile
from urllib.parse import urlparse
from runtime import safe, save, now, MARKER, progress_bar, CLEAR_EOL

from installed_app import resolve_app, package_app, scan_bundle
from runtime import ROOT, CODE_ROOT, ensure
from processes import execute as execute_child, assert_quiescent, assert_idle, tracked_call
LOCAL=ROOT/'.local'


def parse_target(value):
    if value.isdigit():
        return ('store',str(int(value)))
    url=urlparse(value)
    if url.scheme == 'itms-beta' or (url.scheme == 'https' and url.hostname == 'testflight.apple.com'):
        raise ValueError('TestFlight invitations are not IPA download URLs. Install the beta with TestFlight on this Mac, then pass its /Applications/Name.app path.')
    if url.scheme:
        if url.scheme!='https' or url.hostname!='apps.apple.com' or url.username or url.password:
            raise ValueError('Only https://apps.apple.com App Store links are accepted.')
        found=re.search(r'/id([0-9]+)(?:/)?$',url.path)
        if not found:
            raise ValueError('The App Store link has no numeric App ID.')
        return ('store',found.group(1))
    if Path(value).suffix.lower() == '.app':
        return ('installed-app', str(resolve_app(value)))
    path=Path(value).expanduser().resolve()
    if path.suffix.lower()!='.ipa' or not path.is_file():
        raise ValueError('Provide an App Store link, numeric App ID, or existing .ipa, or installed iOS .app.')
    return ('file',str(path))


MAX_IPA_BYTES = 8 * 1024**3
MAX_EXPANDED_BYTES = 32 * 1024**3
MAX_MEMBERS = 100000
MAX_PLIST_BYTES = 8 * 1024**2
MAX_REPORT_BYTES = 16 * 1024**2


def app_identity(info):
    keys = ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion')
    if not isinstance(info, dict) or any(not isinstance(info.get(k), str) or not info[k].strip() for k in keys):
        raise ValueError('App identity/version fields must be nonempty strings.')
    return {k: info[k] for k in keys}


def read_plist(archive, name):
    if archive.getinfo(name).file_size > MAX_PLIST_BYTES:
        raise ValueError('IPA property list exceeds size limit.')
    value = plistlib.loads(archive.read(name))
    if not isinstance(value, dict):
        raise ValueError('IPA property list must be a dictionary.')
    return value


def sha256_file(path):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def ipa_info(path):
    if path.stat().st_size > MAX_IPA_BYTES:
        raise ValueError('IPA exceeds file size limit.')
    with zipfile.ZipFile(path) as z:
        members=z.infolist()
        if len(members)>MAX_MEMBERS or sum(m.file_size for m in members)>MAX_EXPANDED_BYTES:
            raise ValueError('IPA exceeds archive limits.')
        if any(m.file_size < 0 or m.file_size > MAX_EXPANDED_BYTES for m in members):
            raise ValueError('Invalid IPA member size.')
        names=z.namelist()
        if len(names)!=len(set(names)) or z.testzip() is not None:
            raise ValueError('IPA ZIP integrity check failed.')
        mains=[n for n in names if n.startswith('Payload/') and n.count('/')==2 and n.endswith('.app/Info.plist')]
        if len(mains)!=1:
            raise ValueError('Expected exactly one primary app.')
        p=read_plist(z,mains[0])
        return app_identity(p)


def filename_component(value):
    result=re.sub(r'[/\\:\x00-\x1f\x7f]', '-', str(value)).strip(' .')
    if not result:raise ValueError('Empty filename component.')
    return result.encode('utf-8')[:80].decode('utf-8', errors='ignore')

def output_name(path,signature=None):
    if signature is None:
        signature=json.loads(safe(LOCAL/'tools.json').read_text()).get('filename_suffix','loom')
    with zipfile.ZipFile(path) as z:
        name=None
        if 'iTunesMetadata.plist' in z.namelist():
            name=read_plist(z,'iTunesMetadata.plist').get('itemName')
        main=next(n for n in z.namelist() if n.startswith('Payload/') and n.count('/')==2 and n.endswith('.app/Info.plist'))
        info=read_plist(z,main)
        name=name or info.get('CFBundleDisplayName') or info.get('CFBundleName') or info['CFBundleIdentifier']
    return '_'.join(filename_component(v) for v in [name,info['CFBundleShortVersionString'],signature])+'.ipa'


def verify_result(source_info,output,report):
    if report.stat().st_size > MAX_REPORT_BYTES:
        raise ValueError('Decryption report exceeds size limit.')
    data=json.loads(report.read_text())
    if not isinstance(data,dict):
        raise ValueError('Decryption report must be an object.')
    if data.get('complete') is not True or data.get('plaintext_verified') is not True:
        raise ValueError('Decryption lacks complete plaintext verification; not a passed result.')
    count=data.get('encrypted_image_count')
    images=data.get('images')
    if type(count) is not int or count<=0 or not isinstance(images,list) or not images or count>len(images):
        raise ValueError('No verified encrypted images reported.')
    if any(not isinstance(i,dict) or type(i.get('cryptid_after')) is not int or i['cryptid_after']!=0 for i in images):
        raise ValueError('Encrypted image remains in report.')
    output_data=data.get('output')
    if not isinstance(output_data,dict) or not isinstance(output_data.get('sha256'),str):
        raise ValueError('Decryption report has no output hash.')
    if output.stat().st_size > MAX_IPA_BYTES:
        raise ValueError('Output IPA exceeds file size limit.')
    if sha256_file(output)!=output_data['sha256']:
        raise ValueError('Output does not match the decryption report.')
    if ipa_info(output)!=source_info:
        raise ValueError('Output app identity/version differs from input.')
    with zipfile.ZipFile(output) as z:
        if any('SC_Info' in n.split('/') for n in z.namelist()):
            raise ValueError('Account license files remain in output.')
    return {'complete':True,'plaintext_verified':True,
            'encrypted_images':data['encrypted_image_count'],
            'decrypted_pages':data.get('decrypted_page_count'),
            'signature_verified':data.get('signature_verified',False)}


class Pipeline:
    def __init__(self):
        self.id=uuid.uuid4().hex
        self.work=safe(ROOT/'.runtime/runs'/self.id)
        self.record=safe(ROOT/'records'/(self.id+'.json'))
        self.data={'schema':1,'id':self.id,'status':'allocating','started':now(),'cleanup':'pending','steps':[]}
        save(self.record,self.data)
        try:
            for part in ['input','output','tmp','private-logs']:
                safe(self.work/part).mkdir(parents=True,mode=0o700)
        except BaseException as error:
            self.data.update(status='failed',failure_type=type(error).__name__)
            save(self.record,self.data)
            raise
        self.data['status']='running'
        save(self.record,self.data)
        self.env=os.environ.copy()
        # Do not inherit an unrelated secret descriptor from the caller.
        self.env.pop('DEV_IPA_PASSPHRASE_FD',None)
        self.env.update(XDG_STATE_HOME=str(safe(LOCAL/'state')),DEV_IPA_CACHE=str(safe(LOCAL/'cache')),
                        TMPDIR=str(self.work/'tmp'),UNFAIRPLAY_MODEL_DIR=str(safe(LOCAL/'models')))

    def execute(self,stage,command,secret=None,interactive=False,quiet=False,label=None):
        step={'stage':stage,'started':now()};self.data['steps'].append(step);save(self.record,self.data)
        human=label or stage.replace('-',' ')
        inplace=sys.stdout.isatty()
        live=inplace and not interactive
        ticks=[0]
        if interactive:
            print('  '+human,flush=True)
        elif live:
            print('\r  > '+human+'  '+progress_bar(0)+CLEAR_EOL,end='',flush=True)
        def progress():
            if live:
                ticks[0]+=1
                print('\r  > '+human+'  '+progress_bar(ticks[0])+CLEAR_EOL,end='',flush=True)
            elif not interactive:
                print('  '+human+' (working)',flush=True)
        env=self.env.copy();fds=();reader=writer=None
        if secret is not None:
            reader,writer=os.pipe()
            os.write(writer,secret);os.close(writer);writer=None
            env['DEV_IPA_PASSPHRASE_FD']=str(reader);fds=(reader,)
        code=130
        try:
            with (self.work/'private-logs'/(stage+'.stdout')).open('x') as out,(self.work/'private-logs'/(stage+'.stderr')).open('x') as err:
                stdout=subprocess.DEVNULL if quiet else (None if interactive else out)
                stderr=subprocess.DEVNULL if quiet else (None if interactive else err)
                code=execute_child(command, record=self.data, persist=lambda: save(self.record,self.data),
                    terminal=interactive, env=env,cwd=self.work,stdin=None,stdout=stdout,stderr=stderr,pass_fds=fds,
                    progress=None if interactive else progress)
        finally:
            # Clean up and record the step first, so a failed terminal write never leaks a pipe.
            if reader is not None:os.close(reader)
            if writer is not None:os.close(writer)
            step.update(ended=now(),exit_code=code);save(self.record,self.data)
            if live:
                print(('\r  ✓ '+human+CLEAR_EOL) if code==0 else ('\r'+CLEAR_EOL),flush=True)
            elif interactive and code==0:
                print('  ✓ '+human,flush=True)
            elif code==0 and not interactive:
                print('  '+human+' done',flush=True)
        return code

    def close(self,passed):
        assert_quiescent(self.data)
        # Only this newly-created run's disposable directories; never shared .local.
        for name in (['tmp','input'] if passed else ['tmp','input','output']):
            path=safe(self.work/name)
            if path.exists():
                if not shutil.rmtree.avoids_symlink_attacks:raise RuntimeError('Safe deletion unavailable.')
                shutil.rmtree(path)
        self.data.update(status='passed' if passed else 'failed',ended=now(),cleanup='transients-removed')
        save(self.record,self.data)


def tool_config():
    config=json.loads(safe(LOCAL/'tools.json').read_text())
    tools={}
    for name in ['ipatool','unfairplay','keychain-bridge']:
        p=safe(LOCAL/'bin'/name)
        if hashlib.sha256(p.read_bytes()).hexdigest()!=config[name]:
            raise RuntimeError('Tool hash mismatch: '+name)
        tools[name]=str(p)
    return tools


def keychain_account():
    config=json.loads(safe(LOCAL/'tools.json').read_text())
    account=config.get('keychain_account','')
    if not re.fullmatch(r'[0-9a-f]{32}',account):
        raise ValueError('Invalid Keychain scope.')
    return account


def keychain_secret(helper, record, persist):
    p=tracked_call([helper,'get',keychain_account()],record=record,persist=persist,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    if p.returncode==0:
        if not 12<=len(p.stdout)<=4096:raise RuntimeError('Invalid stored passphrase.')
        return p.stdout
    if p.returncode!=44:
        raise RuntimeError('Keychain access failed or was cancelled; no login was retried.')
    raise RuntimeError('Generated unlock key is missing. Restore your own Keychain backup or reset and set up again; there is no user-chosen passphrase.')


def parse_arguments(arguments=None):
    parser=argparse.ArgumentParser(prog='ipa-loom.command', description=__doc__, allow_abbrev=False)
    parser.add_argument('target',nargs='?')
    parser.add_argument('--suffix',help='Optional filename suffix (not a signing identity).')
    parser.add_argument('--login',action='store_true',help='Explicitly refresh Apple authentication in your Terminal.')
    args=parser.parse_args(arguments)
    if args.suffix is not None:
        try:
            filename_component(args.suffix)
        except ValueError as error:
            parser.error(str(error))
    if args.login and not args.target and args.suffix is not None:
        parser.error('--suffix needs a target when used with --login.')
    if args.login and args.target and parse_target(args.target)[0] == 'installed-app':
        parser.error('Use --login separately; installed-app runs do not authenticate or download.')
    return args


def main():
    os.umask(0o077)
    args=parse_arguments()
    ensure()
    with os.fdopen(os.open(safe(ROOT/'.lab.lock'),os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600),'w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        assert_idle(ROOT)
        receipt=safe(ROOT/'cleanup.json')
        if receipt.exists() and json.loads(receipt.read_text()).get('status')=='started':
            raise RuntimeError('Finish the interrupted cleanup before starting another run.')
        tools=tool_config()
        if not args.target and not args.login:
            if not sys.stdin.isatty():raise ValueError('A target is required.')
            args.target=input('App Store URL, App ID, local IPA or installed iOS .app path: ').strip().strip('"\'')
        target=parse_target(args.target) if args.target else None
        if target and not any(safe(LOCAL/'models').glob('*.bin')):
            raise RuntimeError('Reusable model is missing; restore the verified model before dumping.')
        run=Pipeline();passed=False
        installed=None;source_snapshot=None
        try:
            run.data['input_kind']=target[0] if target else 'login'
            save(run.record,run.data)
            if args.login or (target and target[0]=='store'):
                secret=keychain_secret(tools['keychain-bridge'],run.data,lambda: save(run.record,run.data))
                if args.login:
                    if not sys.stdin.isatty():raise RuntimeError('Login requires your Terminal.')
                    code=run.execute('login',[tools['ipatool'],'auth','login'],secret,interactive=True,label='Signing in to the App Store')
                else:
                    code=run.execute('session-check',[tools['ipatool'],'--non-interactive','auth','info'],secret,quiet=True,label='Checking your App Store session')
                if code!=0:raise RuntimeError('Session unavailable or passphrase incorrect. The wrapper will stop; use --login if reauthentication is needed.')
                if target and target[0]=='store':
                    ipa=run.work/'input/source.ipa'
                    if run.execute('download',[tools['ipatool'],'download','--app-id',target[1],'--platform','iphone','--output',str(ipa)],secret,interactive=True,label='Downloading the app')!=0:
                        raise RuntimeError('IPA download failed; the wrapper will not retry or purchase. ipatool may have attempted token renewal.')
                del secret
            if target:
                if target[0]=='installed-app':
                    print('  Packaging the installed app',flush=True)
                    ipa=run.work/'input/source.ipa'
                    installed,source_snapshot=package_app(Path(target[1]),ipa)
                    run.data['source_copy_verified']=True
                    save(run.record,run.data)
                if target[0]=='file':
                    if Path(target[1]).stat().st_size > MAX_IPA_BYTES:
                        raise ValueError('Input IPA exceeds file size limit.')
                    ipa=run.work/'input/source.ipa';shutil.copyfile(target[1],ipa)
                info=ipa_info(ipa);run.data['app']=info;save(run.record,run.data)
                output=run.work/'output'/output_name(ipa,args.suffix);run.data['output_filename']=output.name;report=run.work/'private-logs/decryption-report.json'
                if run.execute('decrypt',[tools['unfairplay'],'decrypt','--input',str(ipa),'--model',str(LOCAL/'models'),'--output',str(output),'--report',str(report),'--strip-account-data'],label='Decrypting the app')!=0:
                    raise RuntimeError('Decryption failed; private diagnostics were retained.')
                run.data['verification']=verify_result(info,output,report);save(run.record,run.data)
                print('  ✓ Verifying the decryption',flush=True)
            passed=True
        except BaseException as e:
            run.data['failure_type']=type(e).__name__
            raise
        finally:
            try:
                if source_snapshot is not None:
                    run.data['installed_app_unchanged']=False
                    if scan_bundle(installed)!=source_snapshot:
                        raise RuntimeError('Installed app changed during this run; no output accepted. Retry after its update finishes.')
                    run.data['installed_app_unchanged']=True
            except BaseException as error:
                passed=False
                run.data['failure_type']=type(error).__name__
                raise
            finally:
                run.close(passed)
                print('  Record: '+str(run.record))
        if passed and target:
            print('\n✓ Done')
            print('  Decrypted app:  '+str(output))
            print('  plaintext_verified=true; not re-signed or installation-tested.')

if __name__=='__main__':
    try:main()
    except KeyboardInterrupt:print('Interrupted.',file=sys.stderr);sys.exit(130)
    except (OSError,ValueError,RuntimeError,KeyError,subprocess.CalledProcessError,zipfile.BadZipFile) as e:
        print('Stopped: '+str(e),file=sys.stderr);sys.exit(1)
