#!/usr/bin/env python3
#
# Rotates and (optionally) compresses Supervisor logs using `logrotate`
#
# See:
#
# * https://www.rounds.com/blog/easy-logging-with-logrotate-and-supervisord/
# * https://gist.github.com/glarrain/6165987
#

import os
import subprocess
import tempfile

from mediawords.util.config import get_config as py_get_config  # MC_REWRITE_TO_PYTHON: rename back to get_config()
from mediawords.util.paths import mc_root_path
from mediawords.util.process import run_alone
from mediawords.util.log import create_logger

# Max. size of a single log file (in bytes)
__LOG_MAX_SIZE = 100 * 1024 * 1024

# Number of old logs to keep
__OLD_LOG_COUNT = 7

l = create_logger(__name__)


# noinspection SpellCheckingInspection
def rotate_supervisor_logs():
    root_path = mc_root_path()
    l.debug('Media Cloud root path: %s' % root_path)

    config = py_get_config()
    child_log_dir = config['supervisor']['childlogdir']
    l.debug('Child log directory: %s' % child_log_dir)

    supervisor_logs_dir = os.path.join(root_path, child_log_dir)
    l.info('Supervisor logs path: %s' % supervisor_logs_dir)

    logrotate_state_file = os.path.join(supervisor_logs_dir, 'logrotate.state')
    l.debug('logrotate state file: %s' % logrotate_state_file)

    if not os.path.isdir(supervisor_logs_dir):
        raise Exception('Supervisor logs directory does not exist at path: %s' % supervisor_logs_dir)

    logrotate_config = '''
%(supervisor_logs_dir)s/*.log {
    size %(log_max_size)d
    rotate %(old_log_count)d
    copytruncate
    compress
    missingok
    notifempty
}
''' % {
        'supervisor_logs_dir': supervisor_logs_dir,
        'log_max_size': __LOG_MAX_SIZE,
        'old_log_count': __OLD_LOG_COUNT,
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
    run_alone(rotate_supervisor_logs)
