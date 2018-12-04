#
# Common Media Cloud code
#

FROM dockermediacloud/mediacloud-perl-python-base:latest

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

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
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
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    #
    # Has to be done separately before anything else because pyre2 depends on it,
    # and Pip is unable to figure out that it has to install Cython first from
    # requirements.txt; also, PyStemmer doesn't build correctly withou Cython
    # installed beforehand
    pip3 install Cython==0.28.5 && \
    \
    #
    # Install the rest
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Move Log::Log4perl configuration
RUN mv /usr/share/perl5/log4perl.conf /etc/
