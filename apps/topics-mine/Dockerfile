#
# Mine topic worker
#

FROM mc2021/topics-base:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/topics-mine/
ENV PERL5LIB="/opt/mediacloud/src/topics-mine/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/topics-mine/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_mine_worker.pl"]
