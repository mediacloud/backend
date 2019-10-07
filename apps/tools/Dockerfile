#
# Various one-off tools
#

FROM dockermediacloud/common:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    #
    # Install the rest of the stuff
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy tools
COPY bin /opt/mediacloud/bin

USER mediacloud

# Run the tool (ENTRYPOINT because the tool's path is to follow)
ENTRYPOINT ["bash", "-c"]
