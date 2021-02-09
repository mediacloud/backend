#
# Generate word2vec snapshot model worker
#

FROM gcr.io/mcback/common:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/word2vec-generate-snapshot-model/
ENV PERL5LIB="/opt/mediacloud/src/word2vec-generate-snapshot-model/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/word2vec-generate-snapshot-model/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["word2vec_generate_snapshot_model_worker.py"]
