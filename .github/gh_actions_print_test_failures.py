import re
import sys
from pathlib import Path

test_log = Path('joblog.txt').read_text().replace('\n', '')

short_failures = re.findall(r'=========================== short test summary.*?.[0-9]{2}s =========================', test_log, flags=re.IGNORECASE)
short_failure_summary = []

verbose_failures = re.findall(r'FAILURES ==.*?== short test summary', test_log, flags=re.IGNORECASE)
verbose_failure_summary = []

if not verbose_failures:
    print('no test failures this run')
    sys.exit(0)

def remove_datetime_string(test_failure):
    return re.sub(r'20.*?[0-9]{7}Z', '\n', test_failure)

for failure in short_failures:
    failure = remove_datetime_string(failure)
    short_failure_summary.append(failure)

for failure in verbose_failures:
    failure = remove_datetime_string(failure)
    verbose_failure_summary.append(failure.replace('FAILURES', 'FAILURE: \n').replace('short test summary', ''))

for failure in short_failure_summary:
    print(failure + '\n')

print('\nTest details: \n')

for failure in verbose_failure_summary:
    print(failure + '\n')
