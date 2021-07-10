#
# RabbitMQ server
#

FROM mc2021/base:latest

# Add RabbitMQ APT repository
RUN \
    #
    # Erlang
    curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | apt-key add - && \
    echo "deb https://packages.erlang-solutions.com/ubuntu focal contrib" \
        > /etc/apt/sources.list.d/rabbitmq-erlang.list && \
    #
    # RabbitMQ
    curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey | apt-key add - && \
    echo "deb https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu focal main" \
        > /etc/apt/sources.list.d/rabbitmq.list && \
    #
    apt-get -y update && \
    true

# Install and hold a specific version of Erlang
# (will be pinned by APT because not all version pairs are compatible; please
# consult the compatibility table in https://www.rabbitmq.com/which-erlang.html
# and check "apt-cache policy erlang-nox | rabbitmq-server" for available
# versions)
RUN \
    export ERLANG_APT_PACKAGE_VERSION="1:23.2.3-1" && \
    apt-get -y --no-install-recommends install \
        "erlang-asn1=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-base=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-crypto=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-eldap=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-ftp=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-inets=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-mnesia=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-os-mon=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-parsetools=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-public-key=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-runtime-tools=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-snmp=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-ssl=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-syntax-tools=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-tftp=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-tools=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-xmerl=$ERLANG_APT_PACKAGE_VERSION" \
    && \
    apt-mark hold erlang* && \
    true

# Install and hold a specific version of RabbitMQ
RUN \
    apt-get -y --no-install-recommends install "rabbitmq-server=3.8.12-1" && \
    apt-mark hold rabbitmq-server && \
    rm -rf /etc/rabbitmq/ && \
    true

# Copy configuration
COPY --chown=rabbitmq:rabbitmq conf/ /etc/rabbitmq/

ENV \
    #
    # Set node name
    RABBITMQ_NODENAME="mediacloud@localhost" \
    #
    # Increase I/O thread pool size to accommodate for a bigger number of connections
    RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="+A 512"

# Create an initial database that we can use to initialize a fresh copy of
# RabbitMQ more quickly
# If a new empty volume gets mounted to /var/lib/rabbitmq/mnesia/ upon
# container start, Docker will copy the files from the container to the volume
COPY bin/initialize_rabbitmq_db.sh /
RUN \
    echo "Creating initial database..." && \
    /initialize_rabbitmq_db.sh && \
    echo "Done creating initial database." && \
    rm /initialize_rabbitmq_db.sh && \
    true

# Mnesia database
VOLUME /var/lib/rabbitmq/

# Server
EXPOSE 5672

# Web management
EXPOSE 15672

# No USER because RabbitMQ changes its user itself

# Run RabbitMQ
CMD ["rabbitmq-server"]
