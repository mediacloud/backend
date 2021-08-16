#
# Temporal server
#

FROM gcr.io/mcback/base:latest

# Install dependencies
RUN \
    apt-get -y --no-install-recommends install \
        libprotobuf17 \
    && \
    true

# Install Temporal server
RUN \
    # Keep version that's being used in sync with temporal-postgresql
    mkdir -p /var/tmp/temporal/ && \
    /dl_to_stdout.sh "https://github.com/temporalio/temporal/releases/download/v1.9.2/temporal_1.9.2_linux_$(dpkg --print-architecture).tar.gz" | \
        tar -zx -C /var/tmp/temporal/ && \
    mv /var/tmp/temporal/temporal-server /var/tmp/temporal/tctl /usr/bin/ && \
    cd / && \
    rm -rf /var/tmp/temporal/ && \
    true

RUN \
    #
    # Install envsubst for generating configuration
    apt-get -y --no-install-recommends install \
        gettext-base \
    && \
    #
    # Install utilities useful for tctl
    apt-get -y --no-install-recommends install \
        jq \
    && \
    #
    # Add unprivileged user the service will run as
    useradd -ms /bin/bash temporal && \
    #
    # Directory for wrapper scripts
    mkdir -p /opt/temporal-server/bin/ && \
    #
    # Directory for configuration (has to be writable to generate final
    # configuration files from templates)
    mkdir -p /opt/temporal-server/config/ && \
    chown temporal:temporal /opt/temporal-server/config/ && \
    #
    # Directories workflow archival
    mkdir -p \
        /var/lib/temporal/archival/temporal/ \
        /var/lib/temporal/archival/visibility/ \
    && \
    chown -R temporal:temporal /var/lib/temporal/ && \
    #
    true

COPY bin/* /opt/temporal-server/bin/
COPY config/* /opt/temporal-server/config/

ENV PATH="/opt/temporal-server/bin:${PATH}" \
    # https://docs.temporal.io/docs/tctl/#environment-variables
    TEMPORAL_CLI_ADDRESS="temporal-server:7233" \
    TEMPORAL_CLI_NAMESPACE="default"

# Archives
VOLUME /var/lib/temporal/

EXPOSE \
    # Port descriptions: https://docs.temporal.io/docs/server-architecture/
    6933 6934 6935 6939 7233 7234 7235 7239 \
    # Prometheus endpoints
    9091 9092 9093 9094

USER temporal

CMD ["temporal.sh"]
