#
# Webapp (API workers)
#

FROM mc2021/common:latest

# Install Python module dependencies
RUN \
    apt-get -y --no-install-recommends install \
        #
        # scipy seems to be looking for Fortran compiler, no idea why
        gfortran \
        libblas-dev \
        liblapack-dev \
    && \
    #
    true

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Install numpy before scipy
RUN \
    pip3 install numpy==1.19.4 && \
    rm -rf /root/.cache/ && \
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
ENV PERL5LIB="/opt/mediacloud/src/webapp-api/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/webapp-api/python:${PYTHONPATH}"

# Plackup port
EXPOSE 9090

USER mediacloud

# Run Plackup
CMD ["plackup.sh"]
