#
# Common Media Cloud code
#

FROM mediacloud-perl-python-base:latest

# Install dependencies
RUN \
    # Add repository for mecab-ipadic-neologd
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 379CE192D401AB61 && \
    apt-add-repository "deb https://dl.bintray.com/pypt/mecab-ipadic-neologd-deb xenial main" && \
    apt-get -y update && \
    #
    # Required by "cffi" Python module
    apt-get -y --no-install-recommends install libffi-dev && \
    #
    # OpenSSL headers for various SSL modules
    apt-get -y --no-install-recommends install libssl-dev && \
    #
    # Japanese language tokenization
    apt-get -y --no-install-recommends install libmecab-dev && \
    apt-get -y --no-install-recommends install mecab && \
    apt-get -y --no-install-recommends install mecab-ipadic-neologd && \
    #
    # Hindi stemming with Hunspell
    apt-get -y --no-install-recommends install hunspell && \
    apt-get -y --no-install-recommends install libhunspell-dev && \
    #
    true

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
