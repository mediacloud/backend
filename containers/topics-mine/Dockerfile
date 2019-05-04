#
# Mine topic worker
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/topics-mine/
ENV PERL5LIB="/opt/mediacloud/src/topics-mine/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/topics-mine/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["topics_mine.pm"]
