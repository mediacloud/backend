#
# Common Media Cloud code
#

FROM dockermediacloud/perl-python-base:latest

# Install mecab-ipadic-neologd (for Japanese language tokenization) first because it's so large
RUN \
    # Add repository for mecab-ipadic-neologd
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 379CE192D401AB61 && \
    echo "deb https://dl.bintray.com/pypt/mecab-ipadic-neologd-deb xenial main" > \
        /etc/apt/sources.list.d/mecab-ipadic-neologd.list && \
    apt-get -y update && \
    # Japanese language tokenization
    apt-get -y --no-install-recommends install libmecab-dev && \
    apt-get -y --no-install-recommends install swig && \
    apt-get -y --no-install-recommends install mecab && \
    apt-get -y --no-install-recommends install mecab-ipadic-neologd && \
    #
    true

# Install the rest of the dependencies
RUN \
    #
    # Required by "cld2-cffi" Python module
    apt-get -y --no-install-recommends install libffi-dev && \
    #
    # OpenSSL headers for various SSL modules
    apt-get -y --no-install-recommends install libssl-dev && \
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
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Install Python dependencies
COPY src/requirements.txt /var/tmp/

RUN \
    cd /var/tmp/ && \
    #
    # cld2-cffi: https://github.com/chartbeat-labs/textacy/issues/94#issuecomment-299656714
    export CFLAGS="-Wno-narrowing" && \
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
    #
    true

# Add user that will be used for running userland apps
RUN useradd -ms /bin/bash mediacloud

RUN \
    #
    # Create directory where sources will be stored in
    mkdir -p /opt/mediacloud/src/ /opt/mediacloud/tests/ && \
    #
    # Create directory where Perl's Inline module will store its stuff && \
    mkdir -p /perl-inline/ && \
    chown -R mediacloud:mediacloud /perl-inline/ && \
    #
    true

# Create convenience link
RUN ln -s /opt/mediacloud /mc

# Copy sources
COPY src/ /opt/mediacloud/src/common/

ENV PERL5LIB="/opt/mediacloud/src/common/perl" \
    PYTHONPATH="/opt/mediacloud/src/common/python" \
    #
    PERL_INLINE_DIRECTORY="/perl-inline/" \
    #
    # /opt/mediacloud/bin is where container images are expected to store executables
    PATH="/opt/mediacloud/bin:${PATH}"

# Test if submodules were checked out
RUN \
    for submodule_file in \
        # Catalan stemmer
        "python/mediawords/languages/ca/snowball_stemmer/stemmer.sbl"                           \
        # Lithuanian stemmer
        "python/mediawords/languages/lt/snowball_stemmer/lithuanian.sbl"                        \
        # Hindi Hunspell dictionary for lemmatizing
        "python/mediawords/languages/hi/hindi-hunspell/dict-hi_IN/hi_IN.dic"                    \
        # Snowball main module
        "python/snowball/python/snowballstemmer/basestemmer.py"                                 \
        # Email templates
        "perl/MediaWords/Util/Mail/Message/Templates/email-templates/activation_needed.html"    \
    ; do \
        if [ ! -f "/opt/mediacloud/src/common/${submodule_file}" ]; then \
            echo && \
            echo "Git submodules (file ${submodule_file}) haven't been checked out, please run:" && \
            echo && \
            echo "    git submodule update --init --recursive" && \
            echo && \
            echo "and then rebuild this image." && \
            echo && \
            exit 1; \
        fi; \
    done

# Symlink Log::Log4perl configuration to where it's going to be found
RUN ln -s /opt/mediacloud/src/common/perl/log4perl.conf /etc/log4perl.conf
