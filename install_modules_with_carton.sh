#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

# Gearman::XS, the dependency of Gearman::JobScheduler, depends on
# Module::Install, but the author of the module (probably) forgot to add it so
# the list of dependencies (https://rt.cpan.org/Ticket/Display.html?id=89690),
# so installing it separately
mkdir -p local/
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ Module::Install

# (Re-)install a newer version of ExtUtils::MakeMaker because otherwise Carton fails with:
#
# Found ExtUtils::MakeMaker 6.90 which doesn't satisfy 6.92.
# ! Installing the dependencies failed: Installed version (6.66) of ExtUtils::MakeMaker is not in range '6.92'
# ! Bailing out the installation for Locale-Country-Multilingual-0.23.
# ! Installing the dependencies failed: Installed version (6.66) of ExtUtils::MakeMaker is not in range '6.92'
# ! Bailing out the installation for Encode-HanConvert-0.33.
# ! Installing the dependencies failed: Module 'Encode::HanConvert' is not installed, Module 'Locale::Country::Multilingual' is not installed
# ! Bailing out the installation for /mediacloud/.
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ ExtUtils::MakeMaker~6.92

# Net::DNS somehow fails to install via Carton
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ Net::DNS

# Sometimes Carton fails with:
#
# <...>
# ! Installing the dependencies failed: Module 'Spiffy' is not installed
# ! Bailing out the installation for Test-Base-0.62.
# <...>
# ! Bailing out the installation for ...
# <...>
#
# so we're installing Spiffy manually
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ Spiffy

# (Re-)install a newer version of CPAN::Meta::Requirements because otherwise Carton (while installing for Perl 5.16) fails with:
#
# <...>
# ! Couldn't find module or a distribution CPAN::Meta::Requirements (2.121)
# ! Installing the dependencies failed: Installed version (2.120630) of
# CPAN::Meta::Requirements is not in range '2.121'
# ! Bailing out the installation for CPAN-Meta-2.141520.
# ! Installing the dependencies failed: Installed version (2.120630) of
# CPAN::Meta::Requirements is not in range '2.121', Installed version
# (2.120630) of CPAN::Meta::Prereqs is not in range '2.132830'
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ CPAN::Meta::Requirements

# (Re-)install a newer version of JSON::PP because otherwise Carton (while installing for Perl 5.16) fails with:
#
# <...>
# ! Couldn't find module or a distribution JSON::PP (2.27202)
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ JSON::PP

# Install missing dependency to HTML::Entities::Interpolate
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm --verbose -L local/ Test::Stream
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm --verbose -L local/ HTML::Entities::Interpolate

# Install GraphViz separately because it fails on Travis CI container builds
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm --verbose -L local/ GraphViz
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm --verbose -L local/ GraphViz2

# Install Gearman::XS separately because it fails on Travis CI container builds
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm --verbose -L local/ Gearman::XS

# Install the rest of the modules; run the command twice because the first
# attempt might fail
source ./script/set_java_home.sh
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install --deployment || {
    echo "First attempt to install CPAN modules failed, trying again..."
    JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install --deployment
}

# Install Mallet-CrfWrapper (don't run unit tests because the web service test
# ends up as a Perl zombie process during the Vagrant test run)
JAVA_HOME=$JAVA_HOME ./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm \
    --local-lib-contained local/ \
    --verbose \
    --notest \
    https://github.com/dlarochelle/Mallet-CrfWrapper/tarball/0.02

echo "Successfully installed Perl and modules for Media Cloud"
