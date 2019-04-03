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

CMD ["/extract_and_vector.py"]
