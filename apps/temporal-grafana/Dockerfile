#
# Grafana for Temporal stats
#

FROM gcr.io/mcback/base:latest

# Install dependencies
RUN \
    apt-get -y --no-install-recommends install \
        libfontconfig1 \
    && \
    true

# Install Grafana
RUN \
    mkdir -p /opt/grafana/ && \
    /dl_to_stdout.sh "https://dl.grafana.com/oss/release/grafana-7.5.5.linux-amd64.tar.gz" | \
        tar -zx -C /opt/grafana/ --strip 1 && \
    true

RUN \
	#
	# Remove sample provisioning
	rm -rf /opt/grafana/conf/provisioning/ && \
	#
	# Add unprivileged user the service will run as
    useradd -ms /bin/bash temporal && \
    mkdir -p \
    	/var/lib/grafana/ \
    	/var/lib/grafana/logs/ \
    	/var/lib/grafana/plugins/ \
    && \
    chown temporal:temporal /var/lib/grafana/ && \
    #
    # Create directory for provisioning dashboards
    mkdir -p /opt/grafana/dashboards/ && \
    #
    true

COPY provisioning/ /opt/grafana/conf/provisioning/
COPY dashboards/dashboards/* /opt/grafana/dashboards/

# Test if submodules were checked out
RUN \
    if [ ! -f "/opt/grafana/dashboards/temporal.json" ]; then \
        echo && \
        echo "Git submodules haven't been checked out, please run:" && \
        echo && \
        echo "    git submodule update --init --recursive" && \
        echo && \
        echo "and then rebuild this image." && \
        echo && \
        exit 1; \
    fi

WORKDIR /opt/grafana/

ENV PATH="/opt/grafana/bin:${PATH}"

EXPOSE 3000

VOLUME /var/lib/grafana/

USER temporal

COPY grafana.ini /opt/grafana/conf/

CMD ["grafana-server", "-config", "/opt/grafana/conf/grafana.ini"]
