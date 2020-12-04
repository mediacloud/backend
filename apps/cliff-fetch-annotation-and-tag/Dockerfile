FROM dockermediacloud/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/cliff-fetch-annotation-and-tag/
ENV PERL5LIB="/opt/mediacloud/src/cliff-fetch-annotation-and-tag/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/cliff-fetch-annotation-and-tag/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

# TODO: merge these files
CMD ["cliff_fetch_annotation_worker.py"]
CMD ["cliff_update_story_tags_worker.py"]