#
# Extract and vector stories
#

FROM dockermediacloud/mediacloud-common:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy extractor worker
COPY bin/extract_and_vector.py /

# FIXME
CMD ["bash", "-c", "while true; do echo extract-and-vector...; sleep 1; done"]
