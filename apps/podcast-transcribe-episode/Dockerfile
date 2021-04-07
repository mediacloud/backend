#
# Fetch podcast episode, convert it (if needed), transcribe and store to the database
#

FROM gcr.io/mcback/common:latest

# Install FFmpeg for manipulating audio files
RUN apt-get -y --no-install-recommends install ffmpeg

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/podcast-transcribe-episode/
ENV PERL5LIB="/opt/mediacloud/src/podcast-transcribe-episode/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/podcast-transcribe-episode/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["podcast_transcribe_episode_worker.py"]
