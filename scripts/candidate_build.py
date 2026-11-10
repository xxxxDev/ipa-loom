#!/usr/bin/env python3
"""Internal candidate build entry: no Apple login, Keychain action, or promotion."""
import json
from pathlib import Path
import sys
from setup import setup

if __name__ == '__main__':
    pins = json.loads(Path(sys.argv[1]).read_text())
    setup(build_only=True, pins=pins)
