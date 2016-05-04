#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

# Set JAVA_HOME
source ./script/set_java_home.sh

# Net::SSLeay is unable to find system's <openssl/err.h> on OS X
if [ `uname` == 'Darwin' ]; then
    OPENSSL_PREFIX="/usr/local/opt/openssl"
else
    OPENSSL_PREFIX="/usr"
fi

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
        Net::AMQP::RabbitMQ~2.000000
fi

# Install dependency modules; run the command twice because the first
# attempt might fail
ATTEMPT=1
CARTON_INSTALL_SUCCEEDED=0
until [ $ATTEMPT -ge 3 ]; do
    OPENSSL_PREFIX=$OPENSSL_PREFIX \
    JAVA_HOME=$JAVA_HOME \
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
