#
# Mine public topic worker
#

FROM dockermediacloud/mediacloud-topics-mine:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# FIXME
CMD ["bash", "-c", "while true; do echo topics-mine-public...; sleep 1; done"]
