#!/bin/bash

#
# Fetch current versions of CPAN modules, upload them to S3
#
# Usage:
#
# 1) Run the script
# 2) You will find a mirror of CPAN modules on https://s3.amazonaws.com/mediacloud-minicpan/minicpan-<YYYYMMDD>/
# 3) Use S3 as CPAN mirror with CPM:
#
#        cpm install \
#            --global \
#            --resolver 02packages \
#            --no-prebuilt \
#            --mirror "$MC_PERL_CPAN_MIRROR" \
#            Your::Module
#

set -u
set -e
set -x

MC_CPAN_S3_PATH="s3://mediacloud-minicpan/minicpan-$(date +%Y%m%d)/"
MC_CPAN_MIRROR="http://mirror.cc.columbia.edu/pub/software/cpan/"
MC_CPAN_DIR="`pwd`/mediacloud-cpan"

RCFILE_PATH="$(mktemp -d)/mediacloud.minicpanrc"
echo "local: $MC_CPAN_DIR" >> "$RCFILE_PATH"
echo "remote: $MC_CPAN_MIRROR" >> "$RCFILE_PATH"
echo "exact_mirror: 1" >> "$RCFILE_PATH"
echo "skip_perl: 1" >> "$RCFILE_PATH"
echo "also_mirror: indices/ls-lR.gz" >> "$RCFILE_PATH"

# Fetch the modules
mkdir -p "$MC_CPAN_DIR"
minicpan -C "$RCFILE_PATH"

# Upload the modules to S3
python3 -m s4cmd \
    dsync \
    --recursive \
    --verbose \
    --num-threads=8 \
    --delete-removed \
    --API-ACL=public-read \
    mediacloud-cpan/ \
    "$MC_CPAN_S3_PATH"
