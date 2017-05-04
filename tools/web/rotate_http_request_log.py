#!/usr/bin/env python3
#
# Rotates and (optionally) compresses HTTP request log using `logrotate`
#
# See:
#

import os
import subprocess
import tempfile

from mediawords.util.paths import mc_root_path
from mediawords.util.process import run_alone
from mediawords.util.log import create_logger

# Max. size of a single log file (in bytes)
__LOG_MAX_SIZE = 2 * 1024 * 1024 * 1024

# Number of old logs to keep
__OLD_LOG_COUNT = 7

l = create_logger(__name__)


# noinspection SpellCheckingInspection
def rotate_http_request_log():
    root_path = mc_root_path()
    l.debug('Media Cloud root path: %s' % root_path)

    logs_dir = os.path.join(root_path, 'data', 'logs')
    if not os.path.isdir(logs_dir):
        raise Exception('Logs directory does not exist at path: %s' % logs_dir)
    l.debug('Logs path: %s' % logs_dir)

    try:
        path_to_xz = subprocess.check_output(['/bin/bash', '-c', 'command -v xz']).decode('utf-8').strip()
    except subprocess.CalledProcessError as ex:
        raise Exception('"xz" not found on the system: %s' % str(ex))
    l.info('Path to "xz": %s' % path_to_xz)

    try:
        path_to_unxz = subprocess.check_output(['/bin/bash', '-c', 'command -v unxz']).decode('utf-8').strip()
    except subprocess.CalledProcessError as ex:
        raise Exception('"unxz" not found on the system: %s' % str(ex))
    l.info('Path to "unxz": %s' % path_to_unxz)

    http_request_log_path = os.path.join(logs_dir, 'http_request.log')
    if not os.path.isfile(http_request_log_path):
        raise Exception('HTTP request log does not exist at path: %s' % http_request_log_path)
    l.info('HTTP request log path: %s' % http_request_log_path)

    logrotate_state_file = os.path.join(logs_dir, 'http_request-logrotate.state')
    l.debug('logrotate state file: %s' % logrotate_state_file)

    logrotate_config = '''
%(http_request_log_path)s {
    daily
    size %(log_max_size)d
    rotate %(old_log_count)d
    copytruncate
    compress
    compresscmd %(path_to_xz)s
    compressext .xz
    compressoptions -9
    uncompresscmd %(path_to_unxz)s
    missingok
    notifempty
}
''' % {
        'http_request_log_path': http_request_log_path,
        'log_max_size': __LOG_MAX_SIZE,
        'old_log_count': __OLD_LOG_COUNT,
        'path_to_xz': path_to_xz,
        'path_to_unxz': path_to_unxz,
    }

    logrotate_temp_fd, logrotate_temp_config_path = tempfile.mkstemp(suffix='.conf', prefix='logrotate')
    l.debug('Temporary logtorate config path: %s' % logrotate_temp_config_path)

    with os.fdopen(logrotate_temp_fd, 'w') as tmp:
        tmp.write(logrotate_config)

    l.info('Running logrotate...')
    subprocess.check_call([
        'logrotate',
        '--verbose',
        '--state', logrotate_state_file,
        logrotate_temp_config_path
    ])

    l.debug('Cleaning up temporary logrotate config...')
    os.unlink(logrotate_temp_config_path)


if __name__ == '__main__':
    run_alone(rotate_http_request_log)
