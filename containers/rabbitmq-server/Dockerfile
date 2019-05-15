#
# RabbitMQ server
#

FROM dockermediacloud/mediacloud-base:latest

# Add Erlang Solutions GPG key
RUN curl -L https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | apt-key add -

# Add RabbitMQ PackageCloud GPG key
RUN curl -L https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey | apt-key add -

# Add Erlang Solutions APT repository
# (RabbitMQ > 3.7 requires newer Erlang than is provided by Ubuntu 16.04)
RUN echo "deb https://packages.erlang-solutions.com/ubuntu xenial contrib" > /etc/apt/sources.list.d/erlang-solutions.list

# Add RabbitMQ APT repository
RUN echo "deb https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ xenial main" > /etc/apt/sources.list.d/rabbitmq.list

# Fetch new repositories
RUN apt-get -y update

# Install and hold a specific version of Erlang
# (will be pinned by APT because not all version pairs are compatible; please
# consult the compatibility table in https://www.rabbitmq.com/which-erlang.html
# and check "apt-cache policy erlang-nox | rabbitmq-server" for available
# versions)
RUN \
    export ERLANG_APT_PACKAGE_VERSION="1:21.0.6-1" && \
    apt-get -y --no-install-recommends install \
        "erlang-asn1=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-base=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-crypto=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-diameter=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-edoc=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-eldap=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-erl-docgen=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-eunit=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-ic=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-inets=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-inviso=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-mnesia=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-nox=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-odbc=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-os-mon=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-parsetools=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-percept=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-public-key=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-runtime-tools=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-snmp=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-ssh=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-ssl=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-syntax-tools=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-tools=$ERLANG_APT_PACKAGE_VERSION" \
        "erlang-xmerl=$ERLANG_APT_PACKAGE_VERSION" \
    && \
    apt-mark hold erlang* && \
    true

# Install and hold a specific version of RabbitMQ
RUN \
    apt-get -y --no-install-recommends install "rabbitmq-server=3.7.7-1" && \
    apt-mark hold rabbitmq-server && \
    true

# Copy configuration
COPY --chown=rabbitmq:rabbitmq conf/* /etc/rabbitmq/

# Copy scripts
COPY bin/initialize_rabbitmq_db.sh /

# Set node name
ENV RABBITMQ_NODENAME="mediacloud@localhost"

# Increase I/O thread pool size to accommodate for a bigger number of connections
ENV RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="+A 512"

# Create a template database that we can use to initialize a fresh copy of
# RabbitMQ more quickly
# If a new empty volume gets mounted to /var/lib/rabbitmq/mnesia/ upon
# container start, Docker will copy the files from the container to the volume
RUN \
    echo "Creating template database..." && \
    /initialize_rabbitmq_db.sh && \
    echo "Done creating template database." && \
    true

# Mnesia database
VOLUME /var/lib/rabbitmq/

# Server
EXPOSE 5672

# Web management
EXPOSE 15672

# Run RabbitMQ
CMD ["rabbitmq-server"]
