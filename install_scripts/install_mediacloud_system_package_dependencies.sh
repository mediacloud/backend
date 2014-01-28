#!/bin/bash

set -u
set -o errexit


CLD_URL_DEBIAN="http://chromium-compact-language-detector.googlecode.com/files/compact-language-detector_0.1-1_amd64.deb"
VAGRANT_URL_DEBIAN="http://files.vagrantup.com/packages/a40522f5fabccb9ddabad03d836e120ff5d14093/vagrant_1.3.5_x86_64.deb"


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
        coreutils postgresql curl tidy libyaml berkeley-db4 gawk cpanminus

    # have to change dir or it think you are trying to install from the supervisor/ dir
    ( cd /tmp; easy_install supervisor )

    sudo cpanm \
        XML::Parser XML::SAX::Expat XML::LibXML XML::LibXML::Simple \
        Test::WWW::Mechanize OpenGL DBD::Pg Perl::Tidy HTML::Parser YAML \
        YAML::LibYAML YAML::Syck List::AllUtils List::MoreUtils Readonly \
        Readonly::XS BerkeleyDB GraphViz Graph Graph::Writer::GraphViz \
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
    sudo apt-get --assume-yes install \
        expat libexpat1-dev libxml2-dev gawk postgresql-server-dev-all \
        postgresql-client libdb-dev libtest-www-mechanize-perl libtidy-dev \
        libopengl-perl libgraph-writer-graphviz-perl libgraphviz-perl \
        graphviz graphviz-dev graphviz-doc libgraphviz-dev libyaml-syck-perl \
        liblist-allutils-perl liblist-moreutils-perl libreadonly-perl \
        libreadonly-xs-perl curl python python-dev python-pip python-lxml \
        python-lxml-dbg python-lxml-doc python-libxml2 libxml2-dev \
        libxslt1-dev libxslt1-dbg libxslt1.1 build-essential make gcc g++ \
        cpanminus perl-doc liblocale-maketext-lexicon-perl openjdk-7-jdk \
        pandoc gearman libgearman-dev

    # Apt's version of Supervisor is too old
    sudo apt-get remove -y supervisor

    # Apt's version of Vagrant is too old
    sudo apt-get remove -y vagrant
    
    # have to change dir or it think you are trying to install from the supervisor/ dir
    ( cd /tmp; sudo easy_install supervisor ) 

    # Install CLD separately
    if [ ! "${SKIP_CLD_TEST:+x}" ]; then     # Not installed manually?
        if [ ! -f /usr/lib/libcld.so ]; then        # Library is not installed yet?

            # Try to download and install
            CLDTEMPDIR=`mktemp -d -t cldXXXXX`
            wget -O "$CLDTEMPDIR/cld.deb" "$CLD_URL_DEBIAN"
            sudo dpkg -i "$CLDTEMPDIR/cld.deb"
            rm -rf "$CLDTEMPDIR"

            if [ ! -f /usr/lib/libcld.so ]; then    # Installed?
                echo "I have tried to install CLD manually but failed."
                echo
                echo_cld_instructions
                exit 1
            fi
        fi
    fi

    # Install an up-to-date version of Vagrant
    if [ ! "${SKIP_VAGRANT_TEST:+x}" ]; then
        if [ ! -x /usr/bin/vagrant ]; then

            # Try to download and install
            VAGRANTTEMPDIR=`mktemp -d -t vagrantXXXXX`
            wget -O "$VAGRANTTEMPDIR/vagrant.deb" "$VAGRANT_URL_DEBIAN"
            sudo dpkg -i "$VAGRANTTEMPDIR/vagrant.deb"
            rm -rf "$VAGRANTTEMPDIR"

            if [ ! -x /usr/bin/vagrant ]; then    # Installed?
                echo "I have tried to install Vagrant manually but failed."
                echo
                echo_vagrant_instructions
                exit 1
            fi
        fi
    fi

fi
