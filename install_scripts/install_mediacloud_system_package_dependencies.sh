#!/bin/bash

set -u
set -o errexit


CLD_URL_DEBIAN="http://chromium-compact-language-detector.googlecode.com/files/compact-language-detector_0.1-1_amd64.deb"
VAGRANT_URL_DEBIAN="https://releases.hashicorp.com/vagrant/1.8.1/vagrant_1.8.1_x86_64.deb"
ERLANG_APT_GPG_KEY_URL="http://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc"
ERLANG_APT_REPOSITORY_URL="http://packages.erlang-solutions.com/ubuntu"
RABBITMQ_PACKAGECLOUD_SCRIPT="https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.deb.sh"


function echo_cld_instructions {
    cat <<EOF
You have to manually download, build and install Chromium Compact Language
Detector library from:

http://code.google.com/p/chromium-compact-language-detector/

When you have done that, make sure that you have libcld.dylib somewhere
(e.g. in /usr/local/lib/libcld.dylib) and run this script again with the
environment variable SKIP_CLD_TEST being set as such:

SKIP_CLD_TEST=1 $0
EOF
}

function echo_vagrant_instructions {
    cat <<EOF
You might want to install Vagrant to set up automatic Media Cloud unit testing
on VirtualBox / Amazon EC2 machines. Download and install Vagrant from:

http://downloads.vagrantup.com/

You don't need Vagrant to run Media Cloud, so install it only if you know what
you're doing.

When you have installed Vagrant (or chose to not install it at all), make sure
that you have "vagrant" binary somewhere (e.g. in /usr/bin/vagrant) and run
this script again with the environment variable SKIP_VAGRANT_TEST being set as
such:

SKIP_VAGRANT_TEST=1 $0
EOF
}

# Version comparison functions
function verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

function verlt() {
    [ "$1" = "$2" ] && return 1 || verlte "$1" "$2"
}


echo "installing media cloud system dependencies"
echo

if [ `uname` == 'Darwin' ]; then

    # Mac OS X

    if [ ! -x /usr/local/bin/brew ]; then
        cat <<EOF
You'll need Homebrew <http://mxcl.github.com/homebrew/> to install the required
packages on Mac OS X. It might be possible to do that manually with
Fink <http://www.finkproject.org/> or MacPorts <http://www.macports.org/>, but
you're at your own here.
EOF
        exit 1
    fi

    if [ ! -x /usr/bin/gcc ]; then
        cat <<EOF
As a dependency to Homebrew, you need to install Xcode (available as a free
download from Mac App Store or from http://developer.apple.com/) and Xcode's
"Command Line Tools" (open Xcode, go to "Xcode" -> "Preferences...", select
"Downloads", choose "Components", click "Install" near the "Command Line Tools"
entry, wait for a while.
EOF
        exit 1
    fi

    brew install \
        graphviz --with-bindings \
        coreutils curl homebrew/dupes/tidy libyaml gawk cpanminus \
        gearman --with-postgresql \
        netcat openssl rabbitmq libyaml

    # have to change dir or it think you are trying to install from the supervisor/ dir
    ( cd /tmp; easy_install supervisor )

    sudo cpanm \
        XML::Parser XML::SAX::Expat XML::LibXML XML::LibXML::Simple \
        Test::WWW::Mechanize OpenGL DBD::Pg Perl::Tidy HTML::Parser YAML \
        YAML::LibYAML YAML::Syck List::AllUtils List::MoreUtils Readonly \
        Readonly::XS GraphViz Graph Graph::Writer::GraphViz \
        HTML::Entities version Lingua::Stem::Snowball

   if [ ! "${SKIP_VAGRANT_TEST:+x}" ]; then
        if [ ! -x /usr/bin/vagrant ]; then
            echo_vagrant_instructions
            exit 1
        fi
    fi

    if [ ! "${SKIP_CLD_TEST:+x}" ]; then
        echo_cld_instructions
        exit 1
    fi

else

    # assume Ubuntu
    source /etc/lsb-release
    sudo apt-get -y install curl

    # Apt's versions of Supervisor, Vagrant, RabbitMQ are too old
    OBSOLETE_APT_PACKAGES=(supervisor vagrant rabbitmq-server)
    for obsolete_package in "${OBSOLETE_APT_PACKAGES[@]}"; do
        dpkg-query -l "$obsolete_package" | grep "^ii" >/dev/null 2>&1 && {
            echo "Installed package '$obsolete_package' from APT is too old, removing..."
            sudo apt-get -y remove $obsolete_package
        }
    done

    # Ubuntu 12.04 APT's version of Erlang is too old (needed by RabbitMQ)
    if verlt "$DISTRIB_RELEASE" "14.04"; then

         # Ubuntu 12.04 APT's version of Erlang is too old
        sudo apt-get -y remove erlang*
        curl "$ERLANG_APT_GPG_KEY_URL" | sudo apt-key add -
        echo "deb $ERLANG_APT_REPOSITORY_URL precise contrib" | \
            sudo tee -a /etc/apt/sources.list.d/erlang-solutions.list
        sudo apt-get -y update
    fi

    # Ubuntu (all versions) APT's version of RabbitMQ is too old
    # (we need 3.5.0+ to support priorities)
    curl -s "$RABBITMQ_PACKAGECLOUD_SCRIPT" | sudo bash

    # Install Gearman from PPA repository
    sudo apt-get -y install python-software-properties

    if verlt "$DISTRIB_RELEASE" "14.04"; then

         # Ubuntu 12.04 APT's version of Gearman is too old
        sudo apt-get -y remove gearman gearman-job-server gearman-tools \
            libgearman-dbg libgearman-dev libgearman-doc libgearman6
        sudo add-apt-repository -y ppa:gearman-developers/ppa
        sudo apt-get -y update
    fi

    sudo apt-get -y install gearman-job-server gearman-tools libgearman-dev

    # Install the rest of the packages
    sudo apt-get --assume-yes install \
        expat libexpat1-dev libxml2-dev gawk postgresql-server-dev-all \
        libdb-dev libtest-www-mechanize-perl libtidy-dev \
        libopengl-perl libgraph-writer-graphviz-perl libgraphviz-perl \
        graphviz graphviz-dev graphviz-doc libgraphviz-dev libyaml-syck-perl \
        liblist-allutils-perl liblist-moreutils-perl libreadonly-perl \
        libreadonly-xs-perl curl python python-dev python-pip python-lxml \
        python-lxml-dbg python-lxml-doc python-libxml2 libxml2-dev \
        libxslt1-dev libxslt1-dbg libxslt1.1 build-essential make gcc g++ \
        cpanminus perl-doc liblocale-maketext-lexicon-perl openjdk-7-jdk \
        pandoc netcat rabbitmq-server libyaml-dev

    # Disable system-wide RabbitMQ server (we will start and use our very own instance)
    sudo update-rc.d rabbitmq-server disable
    sudo service rabbitmq-server stop
    
    # have to change dir or it think you are trying to install from the supervisor/ dir
    ( cd /tmp; sudo easy_install supervisor ) 

    # Install CLD separately
    if [ ! "${SKIP_CLD_TEST:+x}" ]; then     # Not installed manually?
        if [ ! -f /usr/lib/libcld.so ]; then        # Library is not installed yet?

            echo "Installing CLD library..."

            # Try to download and install
            CLD_TEMP_DIR=`mktemp -d -t cldXXXXX`
            CLD_TEMP_FILE="$CLD_TEMP_DIR/cld.deb"

            wget --quiet -O "$CLD_TEMP_FILE" "$CLD_URL_DEBIAN" || {
                echo "Unable to fetch CLD library from $CLD_TEMP_FILE; maybe the URL is outdated?"
                echo
                echo_cld_instructions
                exit 1
            }

            sudo dpkg -i "$CLD_TEMP_FILE" || {
                echo "Unable to install CLD library from $CLD_TEMP_FILE."
                echo
                echo_cld_instructions
                exit 1
            }

            rm -rf "$CLD_TEMP_DIR"

            if [ ! -f /usr/lib/libcld.so ]; then    # Installed?
                echo "I have tried to install CLD library manually but failed."
                echo
                echo_cld_instructions
                exit 1
            fi
        fi
    fi

    # Install an up-to-date version of Vagrant
    if [ ! "${SKIP_VAGRANT_TEST:+x}" ]; then
        if [ ! -x /usr/bin/vagrant ]; then

            echo "Installing Vagrant..."

            # Try to download and install
            VAGRANT_TEMP_DIR=`mktemp -d -t vagrantXXXXX`
            VAGRANT_TEMP_FILE="$VAGRANT_TEMP_DIR/vagrant.deb"

            wget --quiet -O "$VAGRANT_TEMP_FILE" "$VAGRANT_URL_DEBIAN" || {
                echo "Unable to fetch Vagrant from $VAGRANT_URL_DEBIAN; maybe the URL is outdated?"
                echo
                echo_vagrant_instructions
                exit 1
            }

            sudo dpkg -i "$VAGRANT_TEMP_FILE" || {
                echo "Unable to install Vagrant from $VAGRANT_TEMP_FILE."
                echo
                echo_vagrant_instructions
                exit 1
            }

            rm -rf "$VAGRANT_TEMP_DIR"

            if [ ! -x /usr/bin/vagrant ]; then    # Installed?
                echo "I have tried to install Vagrant manually but failed."
                echo
                echo_vagrant_instructions
                exit 1
            fi

            # Install AWS plugin (https://github.com/mitchellh/vagrant-aws)
            vagrant plugin install vagrant-aws --plugin-version 0.5.0
        fi
    fi

fi
