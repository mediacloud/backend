#
# Perl-Python code base
#

FROM mediacloud-python-base:latest

# CPAN mirror URL (CPAN, DarkPan or MiniCPAN)
ENV MEDIACLOUD_PERL_CPAN_MIRROR "https://s3.amazonaws.com/mediacloud-minicpan/minicpan-20170824/"

# Use correct Python with Inline::Python
ENV INLINE_PYTHON_EXECUTABLE /usr/bin/python3.7

# Install Git (for fetching patched Inline::Python) and Perl itself
RUN apt-get -y --no-install-recommends install git perl

# Install cpanminus
RUN curl -L https://cpanmin.us | perl - App::cpanminus

# Install patched Inline::Perl
RUN \
    #
    # Install Inline
    cpanm --mirror "$MEDIACLOUD_PERL_CPAN_MIRROR" --mirror-only Inline && \
    #
    # Install Inline::Python variant which die()s with tracebacks (stack traces)
    cpanm https://github.com/berkmancenter/mediacloud-inline-python-pm.git@v0.56-mediacloud && \
    true
