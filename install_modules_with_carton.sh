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

# Graph::Layout::Aesthetic doesn't compile on newer compilers, so install a
# monkey-patched version of the module beforehand
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ git://github.com/pypt/p5-Graph-Layout-Aesthetic.git@0.12

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

# Install the rest of the modules; run the command twice because the first
# attempt might fail
source ./script/set_java_home.sh
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install --deployment || { echo "First attempt to install CPAN modules might fail"; }
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for Media Cloud"
