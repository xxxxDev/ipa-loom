#!/usr/bin/env python3
"""Validate an IPA Loom date tag without creating a tag or release."""
import datetime
import re
import sys


def validate(value):
    match = re.fullmatch(r'v([0-9]{4})\.([1-9]|1[0-2])\.([1-9]|[12][0-9]|3[01])', value)
    if not match:
        raise ValueError('Use vYYYY.M.D without zero-padding, for example v2026.11.9.')
    datetime.date(*map(int, match.groups()))
    return value


if __name__ == '__main__':
    try:
        print(validate(sys.argv[1]))
    except (IndexError, ValueError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
