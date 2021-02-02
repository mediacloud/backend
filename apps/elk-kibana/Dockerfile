#
# Kibana for ELK logging stack
#

FROM gcr.io/mcback/java-base:latest

# Install headless Chromium dependencies (needed for Reporting)
RUN \
    apt-get -y --no-install-recommends install \
        ca-certificates \
        fonts-freefont-ttf \
        fonts-ipafont-gothic \
        fonts-kacst \
        fonts-liberation \
        fonts-liberation \
        fonts-thai-tlwg \
        fonts-wqy-zenhei \
        gconf-service \
        libappindicator1 \
        libasound2 \
        libatk1.0-0 \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libexpat1 \
        libfontconfig1 \
        libfontconfig1 \
        libgbm1 \
        libgcc1 \
        libgconf-2-4 \
        libgdk-pixbuf2.0-0 \
        libglib2.0-0 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libstdc++6 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxrandr2 \
        libxrender1 \
        libxss1 \
        libxss1 \
        libxtst6 \
        lsb-release \
        xdg-utils \
        xvfb \
    && \
    true

# Install Kibana
# (https://www.elastic.co/downloads/kibana)
ENV ELK_KIBANA_VERSION=7.10.2
RUN \
    mkdir -p /opt/kibana/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/kibana/kibana-${ELK_KIBANA_VERSION}-linux-x86_64.tar.gz" | \
        tar -zx -C /opt/kibana/ --strip 1 && \
    true

# Add unprivileged user the service will run as
RUN useradd -ms /bin/bash elk

# Fix permissions
RUN \
    mkdir -p /opt/kibana/config/ && \
    chown elk:elk /opt/kibana/data/ && \
    true

# Copy over configuration
COPY config/ /opt/kibana/config/
RUN \
    chown elk:elk /opt/kibana/config/ && \
    chmod go-w /opt/kibana/config/kibana.yml && \
    true

COPY bin/kibana.sh /opt/kibana/bin/

# Web server
EXPOSE 5601

USER elk

# Run Kibana via wrapper script
CMD ["/opt/kibana/bin/kibana.sh"]
