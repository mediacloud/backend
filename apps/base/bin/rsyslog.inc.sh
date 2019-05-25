#
# "source /rsyslog.inc.sh" from your bootstrap script to set up rsyslog
#

# Symlink syslog to Docker's STDOUT
rm -f /var/log/syslog
ln -s /dev/stdout /var/log/syslog
chmod 666 /var/log/syslog

# Start rsyslogd
rsyslogd -n &
