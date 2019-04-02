#
# Mine topic worker
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/topics_mine.pm /

# FIXME
CMD ["bash", "-c", "while true; do echo topics-mine...; sleep 1; done"]
