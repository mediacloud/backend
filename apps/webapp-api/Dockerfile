#
# Webapp (API workers)
#

FROM dockermediacloud/common:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    #
    # Install the rest of the stuff
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy FastCGI helpers
COPY bin /opt/mediacloud/bin

# Copy sources
COPY src/ /opt/mediacloud/src/webapp-api/
ENV PERL5LIB="/opt/mediacloud/src/webapp-api/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/webapp-api/python:${PYTHONPATH}"

# Plackup port
EXPOSE 9090

USER mediacloud

# Run Plackup
CMD ["plackup.sh"]
