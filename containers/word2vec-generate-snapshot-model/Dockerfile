#
# Generate word2vec snapshot model worker
#

FROM dockermediacloud/mediacloud-common:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/word2vec_generate_snapshot_model.py /

# FIXME
CMD ["bash", "-c", "while true; do echo word2vec-generate-snapshot-model...; sleep 1; done"]
