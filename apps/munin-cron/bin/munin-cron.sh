#!/bin/bash

set -e

if [ -z "$MC_MUNIN_CRON_ALERT_EMAIL" ]; then
    echo "MC_MUNIN_CRON_ALERT_EMAIL (email address to send email alerts to) is not set."
    exit 1
fi

set -u

# Set up alerting
ALERTS_CONF_FILE="/etc/munin/munin-conf.d/alerts.conf"
echo -n > "${ALERTS_CONF_FILE}"
chmod 644 "${ALERTS_CONF_FILE}"

# Pretty weird way to print a bunch of dollar signs to a file but Munin doesn't make it easy
echo -n 'contact.mediacloud.command ' >> "${ALERTS_CONF_FILE}"
echo -n 'mail -s "[Munin] ' >> "${ALERTS_CONF_FILE}"
echo -n '${if:cfields CRITICAL}${if:wfields WARNING}' >> "${ALERTS_CONF_FILE}"
echo -n '${if:fofields OK}${if:ufields UNKNOWN}' >> "${ALERTS_CONF_FILE}"
echo -n ' -> ${var:graph_title} ' >> "${ALERTS_CONF_FILE}"
echo -n '${if:wfields -> ${loop<,>:wfields ${var:label}=${var:value}}}' >> "${ALERTS_CONF_FILE}"
echo -n '${if:cfields -> ${loop<,>:cfields ${var:label}=${var:value}}}' >> "${ALERTS_CONF_FILE}"
echo -n '${if:fofields -> ${loop<,>:fofields ${var:label}=${var:value}}}' >> "${ALERTS_CONF_FILE}"
echo -n '" ' >> "${ALERTS_CONF_FILE}"

# Escape "@"
echo -n "${MC_MUNIN_CRON_ALERT_EMAIL}" | sed 's/@/\\@/g' >> "${ALERTS_CONF_FILE}"

echo >> "${ALERTS_CONF_FILE}"

# Start Cron daemon wrapper from cron-base
exec /cron.sh
