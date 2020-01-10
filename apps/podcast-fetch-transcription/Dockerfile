#
# Collect due transcriptions from Google Speech API, store them locally as both raw JSON and download text
#

FROM dockermediacloud/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/podcast-fetch-transcription/
ENV PERL5LIB="/opt/mediacloud/src/podcast-fetch-transcription/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/podcast-fetch-transcription/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["podcast_fetch_transcription_worker.py"]
