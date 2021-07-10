#
# Prometheus for Temporal stats
#

FROM mc2021/base:latest

RUN \
    mkdir -p /opt/prometheus/ && \
    /dl_to_stdout.sh "https://github.com/prometheus/prometheus/releases/download/v2.26.0/prometheus-2.26.0.linux-amd64.tar.gz" | \
        tar -zx -C /opt/prometheus/ --strip 1 && \
    true

COPY prometheus.yml /opt/prometheus/

# Add unprivileged user the service will run as
RUN \
    useradd -ms /bin/bash temporal && \
    mkdir -p /opt/prometheus/data/ && \
    chown temporal:temporal /opt/prometheus/data/ && \
    true

WORKDIR /opt/prometheus/

ENV PATH="/opt/prometheus:${PATH}"

EXPOSE 9090

USER temporal

VOLUME /opt/prometheus/data/

CMD ["prometheus"]
