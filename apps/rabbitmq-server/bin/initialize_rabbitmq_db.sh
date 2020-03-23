#!/bin/bash
#
# Start RabbitMQ once, create all the necessary users, vhosts, etc., and then shut it down
#

set -u
set -e

# Start RabbitMQ to configure it
# (started on a different port for the clients to not start thinking that
# RabbitMQ is fully up and running)
TEMP_PORT=12345
RABBITMQ_NODE_PORT=$TEMP_PORT rabbitmq-server &
for i in {1..120}; do
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

# Wait for Erlang process to disappear because rabbitmqctl returns even before
# RabbitMQ itself shuts down properly
while pgrep -u root beam.smp > /dev/null; do
    sleep 0.5
done
