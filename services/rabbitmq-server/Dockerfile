#
# RabbitMQ server
#

FROM mediacloud-base:latest

# Node name
ENV RABBITMQ_NODENAME "mediacloud@localhost"

# Increase I/O thread pool size to accommodate for a bigger number of connections
ENV RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS "+A 512"

# Add Erlang Solutions GPG key
RUN wget -qO - https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | apt-key add -

# Add RabbitMQ GPG key
RUN wget -qO - https://dl.bintray.com/rabbitmq/Keys/rabbitmq-release-signing-key.asc | apt-key add -

# Add Bintray.com GPG key
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 379CE192D401AB61

# Add Erlang Solutions APT repository
# (RabbitMQ > 3.7 requires newer Erlang than is provided by Ubuntu 16.04)
RUN add-apt-repository "deb https://packages.erlang-solutions.com/ubuntu xenial contrib"

# Add RabbitMQ APT repository
RUN add-apt-repository "deb https://dl.bintray.com/rabbitmq/debian xenial main"

# Fetch new repositories
RUN apt-get -y update

# Install packages
RUN \
    #
    # Install RabbitMQ
    # (Some Erlang + RabbitMQ combinations have problems (e.g. OOM with many messages), so the version is pinned)
    apt-get -y --no-install-recommends install "rabbitmq-server=3.7.3*" && \
    true

# Mnesia database
VOLUME /var/lib/rabbitmq/mnesia/

# Copy configuration
COPY --chown=rabbitmq:rabbitmq conf/* /etc/rabbitmq/

# Run server once to configure it
# FIXME move to wrapper script
RUN \
    #
    # Start RabbitMQ, wait for it to start up
    screen -d -m rabbitmq-server && \
    while true; do \
        echo "Waiting for RabbitMQ to start..."; \
        if nc -z -w 10 127.0.0.1 5672; then \
            break; \
        else \
            sleep 1; \
        fi; \
    done && \
    #
    # Add vhost, set permissions
    rabbitmqctl -n "$RABBITMQ_NODENAME" add_vhost "/mediacloud" && \
    rabbitmqctl -n "$RABBITMQ_NODENAME" set_user_tags "mediacloud" "administrator" && \
    rabbitmqctl -n "$RABBITMQ_NODENAME" set_permissions -p "/mediacloud" "mediacloud" ".*" ".*" ".*" && \
    #
    # Stop after initial configuration
    rabbitmqctl -n "$RABBITMQ_NODENAME" stop && \
    pkill screen && \
    true

# Server
EXPOSE 5672

# Web management
EXPOSE 15672

# Start RabbitMQ normally
CMD /usr/sbin/rabbitmq-server
