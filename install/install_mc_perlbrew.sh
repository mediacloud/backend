#!/bin/bash

set -e
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"


if [ `getconf LONG_BIT` != '64' ]; then
    echo "Install failed, you must have a 64 bit OS."
    exit 1
fi

# Apparently Perlbrew's scripts contain a lot of uninitialized variables
set +u

if [ ! -f ~/perl5/perlbrew/bin/perlbrew ]; then
    echo "Installing Perlbrew..."
    curl -LsS http://install.perlbrew.pl | bash
fi

echo "Loading Perlbrew environment variables..."
source ~/perl5/perlbrew/etc/bashrc

echo "Running 'perlbrew init'..."
perlbrew init

PERLBREW_ROOT="${PERLBREW_ROOT:-~/perl5/perlbrew}"

if [ ! -d "$PERLBREW_ROOT/perls/perl-system" ]; then
    SYSTEM_PERL_BIN=`command -v perl`   # `whereis` usually gives looney results
    echo "System Perl binary was found at: $SYSTEM_PERL_BIN"
    SYSTEM_PERL_DIR=`dirname "$SYSTEM_PERL_BIN"`

    echo "Setting up system's Perl in Perlbrew from $SYSTEM_PERL_DIR..."
    mkdir -p "$PERLBREW_ROOT/perls/perl-system"
    ln -s "$SYSTEM_PERL_DIR" "$PERLBREW_ROOT/perls/perl-system/bin"
fi

echo "System's Perl version: `perl -e 'print substr($^V, 1)'`"

MC_PERL_VERSION=`perl $MC_ROOT_DIR/install/perl_version_to_use.pl`
echo "Will set up Media Cloud to use Perl version: $MC_PERL_VERSION"

# "perl-system" should already exist, so if some other version gets chosen, compile and install it
if [ ! -d "$PERLBREW_ROOT/perls/perl-${MC_PERL_VERSION}" ]; then

    # Works on both Ubuntu and OS X
    CPU_CORE_COUNT=`getconf _NPROCESSORS_ONLN`

    echo "Installing Perl ${MC_PERL_VERSION}..."
    nice perlbrew install \
        -j $CPU_CORE_COUNT \
        --verbose `# Perlbrew output should be chatty so that Vagrant provision script does not timeout` \
        "perl-${MC_PERL_VERSION}" \
        -Duseithreads \
        -Dusemultiplicity \
        -Duse64bitint \
        -Duse64bitall \
        -Duseposix \
        -Dusethreads \
        -Duselargefiles \
        -Dccflags=-DDEBIAN
fi

echo "Switching to installed Perl..."
perlbrew switch "perl-${MC_PERL_VERSION}"

if [ ! -f "$PERLBREW_ROOT/bin/cpanm" ]; then
    echo "Installing cpanm..."
    perlbrew install-cpanm
fi

echo "Creating 'mediacloud' library..."
set +e
perlbrew lib create "perl-${MC_PERL_VERSION}@mediacloud"
set -e

echo "Switching to 'mediacloud' library..."
perlbrew switch "perl-${MC_PERL_VERSION}@mediacloud"

echo "Done installing Perl with Perlbrew."

# Set back to "fail on unitialized variables"
set -u
