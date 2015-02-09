#!/bin/bash
#
# Either:
# 1) download Carton dependencies bundle from S3 and extract it as "local/", or
# 2) build the Carton dependencies, bundle them and upload to S3
#
# Links:
# * http://blog.travis-ci.com/2012-12-18-travis-artifacts/
#

set -e
set -o errexit

if [ -z "$ARTIFACTS_AWS_REGION" ]; then
    echo "ARTIFACTS_AWS_REGION is empty, defaulting to 'us-east-1'."
    S3_REGION="us-east-1"
else
    S3_REGION="$ARTIFACTS_AWS_REGION"
fi

if [ -z "$ARTIFACTS_S3_BUCKET" ]; then
    echo "ARTIFACTS_S3_BUCKET is empty, defaulting to 'travis-ci-cache-mediacloud-pypt-lt'."
    S3_BUCKET_NAME="travis-ci-cache-mediacloud-pypt-lt"
else
    S3_BUCKET_NAME="$ARTIFACTS_S3_BUCKET"
fi
S3_PATH="carton-bundles"
S3_PREFIX="local"

# ---

function bundle_id {

    # Kernel architecture, e.g. x86_64
    local OS_ARCH=`uname -m`
    if [ -z "$OS_ARCH" ]; then
        echo "Unable to determine kernel architecture."
        exit 1
    fi

    # Perl version, e.g. 5.016002
    local PERL_VERSION=`perl -e "print $]"`
    if [ -z "$PERL_VERSION" ]; then
        echo "Unable to determine Perl version."
        exit 1
    fi

    # File's "cpanfile" signature, e.g. last modification date or a hash
    local CPANFILE_SIGNATURE=$(sha1sum cpanfile | cut -d " " -f1)
    if [ -z "$CPANFILE_SIGNATURE" ]; then
        echo "Unable to determine file's \"cpanfile\" signature."
        exit 1
    fi

    # File's "cpanfile.snapshot" signature, e.g. last modification date or a hash
    local CPANFILE_SNAPSHOT_SIGNATURE=$(sha1sum cpanfile.snapshot | cut -d " " -f1)
    if [ -z "$CPANFILE_SNAPSHOT_SIGNATURE" ]; then
        echo "Unable to determine file's \"cpanfile.snapshot\" signature."
        exit 1
    fi

    # OS version
    local OS_VERSION="unknown"
    if [ -f /etc/lsb-release ]; then
        source /etc/lsb-release
        if [ -z "$DISTRIB_RELEASE" ]; then
            echo "OS is Ubuntu, but DISTRIB_RELEASE is empty."
            exit 1
        fi
        OS_VERSION="ubuntu_${DISTRIB_RELEASE}"
    elif [ `uname` == 'Darwin' ]; then
        MAC_OS_X_VERSION=`sw_vers -productVersion`
        if [ -z "$MAC_OS_X_VERSION" ]; then
            echo "OS is OS X, but productVersion is empty."
            exit 1
        fi
        OS_VERSION="osx_${MAC_OS_X_VERSION}"
    fi

    local BUNDLE_ID="${OS_VERSION}-${OS_ARCH}-perl_${PERL_VERSION}-cpanfile_${CPANFILE_SIGNATURE}-snapshot_${CPANFILE_SNAPSHOT_SIGNATURE}"
    echo "$BUNDLE_ID"
}

# 'cd' to Media Cloud's root (assuming that this script is stored in './install_scripts/')
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$PWD/../"

if [ ! -d .git ]; then
    echo ".git directory doesn't exist in the current path."
    echo "Either you didn't checkout Media Cloud from the GitHub repository, or you're not in the Media Cloud root path."
    exit 1
fi

BUNDLE_ID=`bundle_id`
echo "Bundle ID: $BUNDLE_ID"

TGZ_FILENAME="${S3_PREFIX}-${BUNDLE_ID}.tgz"
echo "TGZ filename: $TGZ_FILENAME"

BUNDLE_URL="http://${S3_BUCKET_NAME}.s3-website-${S3_REGION}.amazonaws.com/${S3_PATH}/${TGZ_FILENAME}"
echo "Bundle URL: $BUNDLE_URL"

if curl --retry 3 --retry-delay 3 --output /dev/null --silent --head --fail "$BUNDLE_URL" > /dev/null; then

    echo "Bundle at URL exists, fetching and pouring..."
    curl --retry 3 --retry-delay 3 -0 "$BUNDLE_URL" | tar -zx || {
        echo "Bundle exists at the URL, but I've failed to download and pour it, so giving up."
        exit 1
    }

else
    echo "Bundle at URL doesn't exist, building..."
    ./install_modules_with_carton.sh

    echo "Dependencies were build, archiving..."
    tar -czf "$TGZ_FILENAME" local/

    echo "Uploading to S3..."
    travis-artifacts upload \
        --path "$TGZ_FILENAME" \
        --target-path "$S3_PATH/"

    echo "Removing archive..."
    rm "$TGZ_FILENAME"

    echo ""
    echo "Please note that building the Carton modules took a lot of time, so"
    echo "this Travis CI build will most likely fail (as we only have 50"
    echo "minutes to do everything)."
    echo ""
    echo "To rerun the Travis CI build using the cached (packaged) Carton"
    echo "modules, make another Git push."
    echo ""

fi

echo "Done."
