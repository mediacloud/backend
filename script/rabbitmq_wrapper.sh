#!/bin/bash

# Die on error
set -e

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

QUERY_CONFIG="$PWD/../script/run_with_carton.sh $PWD/../script/mediawords_query_config.pl"

# 'cd' to Media Cloud's root (assuming that this script is stored in './script/')
cd "$PWD/../"

# RabbitMQ recommends at least 65536 max. open files
# (https://www.rabbitmq.com/install-debian.html#kernel-resource-limits)
MIN_OPEN_FILES_LIMIT=65536

# Default web interface port
RABBITMQ_WEB_INTERFACE_PORT=15673


log() {
    # to STDERR
    echo "$@" 1>&2
}

rabbitmq_is_enabled() {
    local rabbitmq_is_enabled=`$QUERY_CONFIG "//job_manager/rabbitmq/server/enabled"`
    if [ "$rabbitmq_is_enabled" == "yes" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

rabbitmq_is_installed() {
    local path_to_rabbitmq_server=$(which rabbitmq-server)
    if [ -x "$path_to_rabbitmq_server" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

rabbitmq_is_up_to_date() {
    local actual_version=$(dpkg -s rabbitmq-server | grep Version | awk '{ print $2 }')
    local required_version="3.6.0"
    dpkg --compare-versions "$actual_version" gt "$required_version" || {
        return 1    # "false" in Bash
    }
    return 0    # "true" in Bash
}

max_fd_limit_is_big_enough() {
    if [ `ulimit -S -n` -ge "$MIN_OPEN_FILES_LIMIT" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

print_rabbitmq_installation_instructions() {
    log "Please install RabbitMQ by running:"
    log ""
    log "    # Erlang (outdated on Ubuntu 12.04)"
    log "    sudo apt-get -y remove esl-erlang* erlang*"
    log "    curl http://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | sudo apt-key add -"
    log "    echo \"deb http://packages.erlang-solutions.com/ubuntu precise contrib\" | sudo tee -a /etc/apt/sources.list.d/erlang-solutions.list"
    log ""
    log "    # RabbitMQ (outdated on all Ubuntu versions)"
    log "    sudo apt-get -y remove rabbitmq-server"
    log "    curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.deb.sh | sudo bash"
    log ""    
    log "    sudo apt-get -y update"
    log "    sudo apt-get -y install rabbitmq-server"
    log ""
}

#
# ---
#

echo "Testing environment..."
if ! rabbitmq_is_enabled; then
    log "RabbitMQ is not enabled."
    log "Please enable it in 'mediawords.yml' by setting /job_manager/rabbitmq/server/enabled to 'yes'."
    exit 0
fi

if ! rabbitmq_is_installed; then
    log "'rabbitmq-server' was not found in your PATH."
    print_rabbitmq_installation_instructions
    exit 1
fi

if [ `uname` == 'Darwin' ]; then
    # Mac OS X -- trust that Homebrew has the latest version, don't mind the open files limit
    :
else
    # Ubuntu

    if ! rabbitmq_is_up_to_date; then
        log "'rabbitmq-server' was found in your PATH, but is too old."
        print_rabbitmq_installation_instructions
        exit 1
    fi

    if ! max_fd_limit_is_big_enough; then
        log "Open file limit is less than $MIN_OPEN_FILES_LIMIT."
        log "Please rerun ./install_scripts/set_kernel_parameters.sh"
        exit 1
    fi
fi

echo "Looking for binaries..."
if [ `uname` == 'Darwin' ]; then
    PATH_TO_RABBITMQ_SERVER="/usr/local/sbin/rabbitmq-server"
    PATH_TO_RABBITMQCTL="/usr/local/sbin/rabbitmqctl"
else
    # Ubuntu has a wrapper script under /usr/sbin that insists we run RabbitMQ
    # as root, but we don't want that
    PATH_TO_RABBITMQ_SERVER="/usr/lib/rabbitmq/bin/rabbitmq-server"
    PATH_TO_RABBITMQCTL="/usr/lib/rabbitmq/bin/rabbitmqctl"
fi
if [ ! -x "$PATH_TO_RABBITMQ_SERVER" ]; then 
    log "Unable to find (execute) rabbitmq-server under $PATH_TO_RABBITMQ_SERVER."
    exit 1
fi
if [ ! -x "$PATH_TO_RABBITMQCTL" ]; then
    log "Unable to find (execute) rabbitmqctl under $PATH_TO_RABBITMQCTL."
    exit 1
fi


echo "Reading configuration..."

# (scope of the following exports is local)

export RABBITMQ_NODE_IP_ADDRESS=`$QUERY_CONFIG "//job_manager/rabbitmq/server/listen"`
export RABBITMQ_NODE_PORT=`$QUERY_CONFIG "//job_manager/rabbitmq/server/port"`
export RABBITMQ_NODENAME=`$QUERY_CONFIG "//job_manager/rabbitmq/server/node_name"`

# Not exported, will be (re)created later
RABBITMQ_USERNAME=`$QUERY_CONFIG "//job_manager/rabbitmq/server/username"`
RABBITMQ_PASSWORD=`$QUERY_CONFIG "//job_manager/rabbitmq/server/password"`
RABBITMQ_VHOST=`$QUERY_CONFIG "//job_manager/rabbitmq/server/vhost"`

export RABBITMQ_BASE="$PWD/data/rabbitmq"
if [ ! -d "$RABBITMQ_BASE" ]; then
    log "RabbitMQ base directory '$RABBITMQ_BASE' does not exist."
    exit 1
fi

export RABBITMQ_CONFIG_FILE="${RABBITMQ_BASE}/rabbitmq"   # sans ".config" extension
if [ ! -f "${RABBITMQ_CONFIG_FILE}.config" ]; then
    log "RabbitMQ configuration file '$RABBITMQ_CONFIG_FILE' does not exist."
    exit 1
fi

export RABBITMQ_MNESIA_BASE="${RABBITMQ_BASE}/mnesia"
if [ ! -d "$RABBITMQ_MNESIA_BASE" ]; then
    log "RabbitMQ Mnesia directory '$RABBITMQ_MNESIA_BASE' does not exist."
    exit 1    
fi

export RABBITMQ_LOG_BASE="${RABBITMQ_BASE}/logs"
if [ ! -d "$RABBITMQ_LOG_BASE" ]; then
    log "RabbitMQ log directory '$RABBITMQ_LOG_BASE' does not exist."
    exit 1    
fi

export RABBITMQ_ENABLED_PLUGINS_FILE="${RABBITMQ_BASE}/enabled_plugins"
if [ ! -f "${RABBITMQ_ENABLED_PLUGINS_FILE}" ]; then
    log "RabbitMQ enabled plugins file '$RABBITMQ_ENABLED_PLUGINS_FILE' does not exist."
    exit 1
fi

# On Ctrl+C, shutdown RabbitMQ
function kill_rabbitmq {
    echo "Killing RabbitMQ at group PID $RABBITMQ_PID..."
    pkill -P $RABBITMQ_PID
}
trap kill_rabbitmq SIGINT

echo "Starting rabbitmq-server..."
$PATH_TO_RABBITMQ_SERVER &
RABBITMQ_PID=$!

echo "Waiting for RabbitMQ to start..."
RABBITMQ_IS_UP=0
RABBITMQ_START_RETRIES=90

echo "Waiting $RABBITMQ_START_RETRIES seconds for RabbitMQ to start..."
for i in `seq 1 $RABBITMQ_START_RETRIES`; do
    echo "Trying to connect (#$i)..."
    if nc -z -w 10 127.0.0.1 $RABBITMQ_NODE_PORT; then
        RABBITMQ_IS_UP=1
        break
    else
        # Still down
        sleep 1
    fi
done

if [ $RABBITMQ_IS_UP = 1 ]; then
    echo "RabbitMQ is up at PID $RABBITMQ_PID."
else
    echo "RabbitMQ is down after $RABBITMQ_START_RETRIES seconds, giving up."
    pkill -9 -P $RABBITMQ_PID
    exit 1
fi

echo "Reconfiguring instance..."

# Create vhost and user
CURRENT_VHOSTS=`$PATH_TO_RABBITMQCTL -n "$RABBITMQ_NODENAME" list_vhosts | tail -n +2 | awk '{ print $1 }'`
if ! echo "$CURRENT_VHOSTS" | grep -Fxq "$RABBITMQ_VHOST"; then
    $PATH_TO_RABBITMQCTL -n "$RABBITMQ_NODENAME" add_vhost "$RABBITMQ_VHOST"
fi

CURRENT_USERS=`$PATH_TO_RABBITMQCTL -n "$RABBITMQ_NODENAME" list_users | tail -n +2 | awk '{ print $1 }'`
if ! echo "$CURRENT_USERS" | grep -Fxq "$RABBITMQ_USERNAME"; then
    $PATH_TO_RABBITMQCTL -n "$RABBITMQ_NODENAME" add_user "$RABBITMQ_USERNAME" "$RABBITMQ_PASSWORD"
fi

$PATH_TO_RABBITMQCTL -n "$RABBITMQ_NODENAME" set_user_tags "$RABBITMQ_USERNAME" "administrator"
$PATH_TO_RABBITMQCTL -n "$RABBITMQ_NODENAME" set_permissions -p "$RABBITMQ_VHOST" "$RABBITMQ_USERNAME" ".*" ".*" ".*"

# Wait forever
echo "RabbitMQ is ready"
cat
