#
# Collect due transcripts from Google Speech API, store them locally as both raw JSON and download text
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
COPY src/ /opt/mediacloud/src/podcast-fetch-transcript/
ENV PERL5LIB="/opt/mediacloud/src/podcast-fetch-transcript/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/podcast-fetch-transcript/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["podcast_fetch_transcript_worker.py"]
