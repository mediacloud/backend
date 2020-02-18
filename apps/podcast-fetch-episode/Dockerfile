#
# Fetch podcast episode from story, read metadata, store it to GCS
#

FROM dockermediacloud/common:latest

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
COPY src/ /opt/mediacloud/src/podcast-fetch-episode/
ENV PERL5LIB="/opt/mediacloud/src/podcast-fetch-episode/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/podcast-fetch-episode/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["podcast_fetch_episode_worker.py"]
