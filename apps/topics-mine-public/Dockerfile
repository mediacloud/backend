#
# Mine public topic worker
#

FROM dockermediacloud/topics-mine:latest

# Copy sources
COPY src/ /opt/mediacloud/src/topics-mine-public/
ENV PERL5LIB="/opt/mediacloud/src/topics-mine-public/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/topics-mine-public/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_mine_public_worker.pl"]
