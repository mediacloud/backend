#
# Submit a long running operation to Google Speech to Text API for it to transcribe the episode
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
COPY src/ /opt/mediacloud/src/podcast-submit-operation/
ENV PERL5LIB="/opt/mediacloud/src/podcast-submit-operation/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/podcast-submit-operation/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["podcast_submit_operation_worker.py"]
