FROM gcr.io/mcback/base:release

RUN \
    mkdir -p /opt/alertmanager/ && \
    /dl_to_stdout.sh "https://github.com/prometheus/alertmanager/releases/download/v0.24.0/alertmanager-0.24.0.linux-$(dpkg --print-architecture).tar.gz" | \
        tar -zx -C /opt/alertmanager/ --strip 1 && \
    true

COPY alertmanager.yml /opt/alertmanager/alertmanager.yml

# Add unprivileged user the service will run as
RUN \
    useradd -ms /bin/bash temporal && \
    mkdir -p /opt/alertmanager/data/ && \
    chown temporal:temporal /opt/alertmanager/data/ && \
    true

WORKDIR /opt/alertmanager/

ENV PATH="/opt/alertmanager:${PATH}"

EXPOSE 9093

USER temporal

VOLUME /opt/alertmanager/data

CMD ["alertmanager"]