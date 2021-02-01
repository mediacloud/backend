#
# Perl-Python code base
#

FROM gcr.io/mcback/base:latest

# Install Python
RUN \
    apt-get -y --no-install-recommends install \
        build-essential \
        python3 \
        python3-dev \
        python3-pip \
    && \
    true

ENV \
    #
    # CPAN mirror URL (CPAN, DarkPan or MiniCPAN)
    MC_PERL_CPAN_MIRROR="https://s3.amazonaws.com/mediacloud-minicpan/minicpan-20170824/" \
    #
    # Use correct Python with Inline::Python
    INLINE_PYTHON_EXECUTABLE=/usr/bin/python3

# Install Git (for fetching patched Inline::Python) and Perl itself
RUN apt-get -y --no-install-recommends install git perl

# Install CPM (newer rewrite of cpanminus with parallel support)
RUN \
    /dl_to_stdout.sh https://raw.githubusercontent.com/skaji/cpm/0.988/cpm > /usr/bin/cpm && \
    chmod +x /usr/bin/cpm && \
    true

# Install patched Inline::Perl
RUN \
    #
    # Install Inline
    cpm install \
        --global \
        --resolver 02packages \
        --no-prebuilt \
        --mirror "$MC_PERL_CPAN_MIRROR" \
        # Explicitly run tests for this code module:
        --test \
        Inline && \
    #
    # Install Inline::Python variant which die()s with tracebacks (stack traces)
    cpm install \
        --global \
        --resolver 02packages \
        --no-prebuilt \
        --mirror "$MC_PERL_CPAN_MIRROR" \
        # Explicitly run tests for this code module:
        --test \
        https://github.com/mediacloud/inline-python-pm.git@v0.56.2-mediacloud && \
    #
    # Cleanup
    rm -rf /root/.perl-cpm/ && \
    #
    true
