FROM dockermediacloud/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/cliff-fetch-annotation-and-tag/
ENV PERL5LIB="/opt/mediacloud/src/cliff-fetch-annotation-and-tag/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/cliff-fetch-annotation-and-tag/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["cliff_tags_from_annotation_worker.py"]