#
# Table dump script
#

FROM gcr.io/mcback/common:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Copy extractor worker
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["dump_table.pl"]
