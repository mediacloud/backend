#!/bin/bash

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

# Net::SSLeay is unable to find system's <openssl/err.h> on OS X
if [ `uname` == 'Darwin' ]; then
    OPENSSL_PREFIX="/usr/local/opt/openssl"
else
    OPENSSL_PREFIX="/usr"
fi

# needed to install the https github links below
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm Test::RequiresInternet
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm \
    --local-lib-contained local/ \
    --verbose \
    Test::RequiresInternet
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm LWP::Protocol::https
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm \
    --local-lib-contained local/ \
    --verbose \
    LWP::Protocol::https

# OS X no longer provides OpenSSL headers and Net::AMQP::RabbitMQ doesn't care
# about OPENSSL_PREFIX so we need to set CCFLAGS and install the module
# separately.
#
# Additionally, we reset LD to just "cc" in order to remove
# MACOSX_DEPLOYMENT_TARGET parameter.
if [ `uname` == 'Darwin' ]; then
    ./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm \
        --configure-args="CCFLAGS=\"-I${OPENSSL_PREFIX}/include\" LDFLAGS=\"-L${OPENSSL_PREFIX}/lib\" LD=\"env cc\"" \
        --local-lib-contained local/ \
        --verbose \
        --notest \
        Net::AMQP::RabbitMQ~2.100001
fi

# Carton is unable to find PkgConfig~0.14026 in a conventional way
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm \
    --local-lib-contained local/ \
    --verbose \
    https://github.com/PerlPkgConfig/perl-PkgConfig/archive/8108f685b45423397f3448e03f369ad9a8311a93.tar.gz

# Inline::Python needs to use virtualenv's Python 3 instead of the default Python2
set +u; source mc-venv/bin/activate; set -u
INLINE_PYTHON_EXECUTABLE=`command -v python3`   # `which` is a liar
echo "Installing Inline::Python with Python executable: $INLINE_PYTHON_EXECUTABLE"

# Install Inline::Python variant which die()s with tracebacks (stack traces)
INLINE_PYTHON_EXECUTABLE=$INLINE_PYTHON_EXECUTABLE \
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm \
    --local-lib-contained local/ \
    --verbose \
    "https://github.com/berkmancenter/mediacloud-inline-python-pm.git@exception_traceback_memleak"

# Fixes: Can't locate XML/SAX.pm in @INC
# https://rt.cpan.org/Public/Bug/Display.html?id=62289
unset MAKEFLAGS

# Install dependency modules; run the command twice because the first
# attempt might fail
ATTEMPT=1
CARTON_INSTALL_SUCCEEDED=0
until [ $ATTEMPT -ge 3 ]; do
    OPENSSL_PREFIX=$OPENSSL_PREFIX \
    INLINE_PYTHON_EXECUTABLE=$INLINE_PYTHON_EXECUTABLE \
    ./script/run_carton.sh install && {
        echo "Successfully installed Carton modules"
        CARTON_INSTALL_SUCCEEDED=1
        break
    } || {
        echo "Attempt $ATTEMPT to install Carton modules failed"
    }
    ATTEMPT=$[$ATTEMPT+1]
done
if [ $CARTON_INSTALL_SUCCEEDED -ne 1 ]; then
    echo "Gave up installing Carton modules."
    exit 1
fi

echo "Successfully installed Perl and modules for Media Cloud"
