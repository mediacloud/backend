#
# Extract and vector stories
#

FROM gcr.io/mcback/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/extract-and-vector/
ENV PERL5LIB="/opt/mediacloud/src/extract-and-vector/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/extract-and-vector/python:${PYTHONPATH}"

# Copy extractor worker
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["extract_and_vector_worker.py"]
