#
# Base image for topic-related code
#

FROM dockermediacloud/mediacloud-common:latest

# Install dependencies
RUN \
    #
    # Probably required by pyre2
    apt-get -y --no-install-recommends install libre2-dev && \
    #
    true

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpanm \
        --mirror "$MEDIACLOUD_PERL_CPAN_MIRROR" \
        --mirror-only \
        --notest \
        --installdeps \
        . && \
    rm cpanfile && \
    rm -rf /root/.cpanm/ && \
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

# Copy sources
COPY src/ /opt/mediacloud/src/topics-base/
ENV PERL5LIB="/opt/mediacloud/src/topics-base/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/topics-base/python:${PYTHONPATH}"
