#!/usr/bin/env python3
"""Run one command on its own terminal for a caller that has none (the Mac app).

    terminal_bridge.py COMMAND [ARGUMENT ...]

The command gets a private pseudo-terminal as its controlling terminal, so its prompts
(Apple sign-in, sudo) behave exactly as in Terminal. What it prints goes to this process's
standard output; what arrives on standard input is typed to it. Nothing passing through is
stored, logged or inspected.

Standard error carries one line, "echo=0" or "echo=1", each time the command turns typed
echo off or on: echo is off while it reads a password, so the caller can hide the field.
An interrupt or terminate signal is typed to the command as Control-C. If the caller goes
away (standard input closes), the command is told there is no more input and, should it
still be running a few seconds later, gets Control-C: it is never left waiting for an answer
nobody can give. The exit code is the command's own, or 128 plus the signal that ended it.
"""
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time


def main(command):
    if not command:
        print('Usage: terminal_bridge.py COMMAND [ARGUMENT ...]', file=sys.stderr)
        return 2
    child, master = pty.fork()
    if child == 0:
        try:
            os.execv(command[0], command)
        finally:
            os._exit(127)
    try:
        # A plain 100-column screen, so progress output has a width to draw to.
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 100, 0, 0))
    except OSError:
        pass
    wake_read, wake_write = os.pipe()
    os.set_blocking(wake_write, False)

    def interrupt(*_):
        try:
            os.write(wake_write, b'i')
        except OSError:
            pass
    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)
    echo = None
    sources = [master, 0, wake_read]
    interrupt_at = None
    listening = True
    while True:
        try:
            ready, _, _ = select.select(sources, [], [], 0.2)
        except InterruptedError:
            continue
        try:
            state = bool(termios.tcgetattr(master)[3] & termios.ECHO)
        except termios.error:
            state = echo
        if state != echo:
            echo = state
            os.write(2, b'echo=1\n' if echo else b'echo=0\n')
        if interrupt_at is not None and time.monotonic() >= interrupt_at:
            interrupt_at = None
            os.write(master, b'\x03')
        if wake_read in ready:
            os.read(wake_read, 64)
            os.write(master, b'\x03')
        if 0 in ready:
            data = os.read(0, 4096)
            if data:
                while data:
                    data = data[os.write(master, data):]
            else:
                # The caller is gone: end the command's input, then interrupt it if it stays.
                sources.remove(0)
                os.write(master, b'\x04')
                interrupt_at = time.monotonic() + 5
        if master in ready:
            try:
                data = os.read(master, 65536)
            except OSError as error:
                # macOS reports the command's end as an input/output error on its terminal.
                if error.errno != errno.EIO:
                    raise
                data = b''
            if not data:
                break
            while data and listening:
                try:
                    data = data[os.write(1, data):]
                except BrokenPipeError:
                    # Nobody is reading any more: keep draining so the command can finish.
                    listening = False
    _, status = os.waitpid(child, 0)
    return os.waitstatus_to_exitcode(status) if os.WIFEXITED(status) else 128 + os.WTERMSIG(status)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
