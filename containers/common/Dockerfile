#
# Common Media Cloud code
#

FROM mediacloud-perl-python-base:latest

# Install OpenSSL headers for various SSL modules
RUN apt-get -y --no-install-recommends install libssl-dev

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Install Perl dependencies
RUN \
    cd /usr/share/perl5/ && \
    cpanm \
        --mirror "$MEDIACLOUD_PERL_CPAN_MIRROR" \
        --mirror-only \
        --notest \
        --verbose \
        --installdeps \
        . && \
    rm cpanfile && \
    rm -rf /root/.cpanm/ && \
    true

# Install Python dependencies
RUN \
    cd /usr/lib/python3/dist-packages/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Move Log::Log4perl configuration
RUN mv /usr/share/perl5/log4perl.conf /etc/

CMD ["sleep", "100000000"]
