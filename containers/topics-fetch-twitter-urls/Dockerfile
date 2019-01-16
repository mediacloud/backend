#
# Fetch Twitter URLs
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# FIXME
CMD ["bash", "-c", "while true; do echo topics-fetch-link...; sleep 1; done"]
