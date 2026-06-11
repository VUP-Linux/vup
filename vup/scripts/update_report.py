#!/usr/bin/env python3
"""Append a build result entry to a JSON report file."""
import json
import sys
import os


def main():
    report_file = sys.argv[1]
    pkg = sys.argv[2]
    status = sys.argv[3]
    log_file = sys.argv[4]

    log_content = ''
    if os.path.exists(log_file):
        try:
            with open(log_file, 'r', errors='replace') as f:
                lines = f.readlines()
                log_content = ''.join(lines[-50:])
        except Exception as e:
            log_content = f'Error reading log: {e}'

    if status == 'success':
        log_content = ''

    with open(report_file, 'r+') as f:
        data = json.load(f)
        data.append({'package': pkg, 'status': status, 'log': log_content})
        f.seek(0)
        json.dump(data, f)
        f.truncate()


if __name__ == '__main__':
    main()
