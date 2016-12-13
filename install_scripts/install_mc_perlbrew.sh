#!/bin/bash

set -e
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

# Perl version to install
PERL_INSTALL_VERSION="5.22.1"

# Works on both Ubuntu and OS X
CPU_CORE_COUNT=`getconf _NPROCESSORS_ONLN`

# Apparently Perlbrew's scripts contain a lot of uninitialized variables
set +u

if [ `getconf LONG_BIT` != '64' ]; then
    echo "Install failed, you must have a 64 bit OS."
    exit 1
fi

echo "Installing Perlbrew..."
curl -LsS http://install.perlbrew.pl | bash

echo "Loading Perlbrew environment variables..."
source ~/perl5/perlbrew/etc/bashrc

echo "Running 'perlbrew init'..."
perlbrew init

echo "Running 'perlbrew install'..."
nice perlbrew install \
	-j $CPU_CORE_COUNT \
	--verbose `# Perlbrew output should be chatty so that Vagrant provision script does not timeout` \
	"perl-${PERL_INSTALL_VERSION}" \
	-Duseithreads \
	-Dusemultiplicity \
	-Duse64bitint \
	-Duse64bitall \
	-Duseposix \
	-Dusethreads \
	-Duselargefiles \
	-Dccflags=-DDEBIAN

echo "Switching to installed Perl..."
perlbrew switch "perl-${PERL_INSTALL_VERSION}"

echo "Installing cpanm..."
perlbrew install-cpanm

echo "Creating 'mediacloud' library..."
perlbrew lib create mediacloud

echo "Switching to 'mediacloud' library..."
perlbrew switch "perl-${PERL_INSTALL_VERSION}@mediacloud"

echo "Done installing Perl with Perlbrew."

# Set back to "fail on unitialized variables"
set -u
