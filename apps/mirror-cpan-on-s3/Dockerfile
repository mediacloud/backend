#
# Script to mirror CPAN to S3 for easier Perl dependencies installing
#

FROM dockermediacloud/perl-python-base:latest

# Install dependencies
RUN \
    pip3.7 install s4cmd && \
    cpanm CPAN::Mini && \
    true

COPY bin/mirror-cpan-on-s3.sh /

CMD ["/mirror-cpan-on-s3.sh"]
