#!/bin/bash
#
# Run RabbitMQ
#

set -u
set -e

# Node name
export RABBITMQ_NODENAME="mediacloud@localhost"

# Increase I/O thread pool size to accommodate for a bigger number of connections
export RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="+A 512"

# If this file exists, we'll assume that RabbitMQ has been configured already
CONFIGURED_FOR_MEDIACLOUD_FILE=/var/lib/rabbitmq/configured-for-mediacloud

if [ ! -f $CONFIGURED_FOR_MEDIACLOUD_FILE ]; then

    # Start RabbitMQ to configure it
    # (started on a different port for the clients to not start thinking that
    # RabbitMQ is fully up and running)
    TEMP_PORT=12345
    RABBITMQ_NODE_PORT=$TEMP_PORT rabbitmq-server &
    while true; do
        echo "Waiting for RabbitMQ to start..."
        if nc -z -w 10 127.0.0.1 $TEMP_PORT; then
            break
        else
            sleep 1
        fi
    done

    # Add vhost, set permissions
    rabbitmqctl -n "$RABBITMQ_NODENAME" add_vhost "/mediacloud" || echo "Vhost already exists?"
    rabbitmqctl -n "$RABBITMQ_NODENAME" set_user_tags "mediacloud" "administrator"
    rabbitmqctl -n "$RABBITMQ_NODENAME" set_permissions -p "/mediacloud" "mediacloud" ".*" ".*" ".*"

    # Stop after initial configuration
    rabbitmqctl -n "$RABBITMQ_NODENAME" stop
    sleep 1

    touch $CONFIGURED_FOR_MEDIACLOUD_FILE

fi

# Start RabbitMQ normally
exec rabbitmq-server
