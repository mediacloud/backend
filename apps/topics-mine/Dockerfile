#
# Mine topic worker
#

FROM dockermediacloud/topics-base:latest

# Install dependencies
RUN \
    #
    curl -o /usr/local/bin/googler https://raw.githubusercontent.com/jarun/googler/v4.0/googler && \
    chmod +x /usr/local/bin/googler && \
    #
    true

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

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
