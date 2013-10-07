#!/bin/bash

set -u
set -o errexit

echo "installing media cloud system dependencies"
echo

if [ `uname` == 'Darwin' ]; then

    # Mac OS X

    if [ ! -x /usr/local/bin/brew ]; then
        echo "You'll need Homebrew <http://mxcl.github.com/homebrew/> to install the required packages on Mac OS X."
        echo "It might be possible to do that manually with Fink <http://www.finkproject.org/>"
        echo "or MacPorts <http://www.macports.org/>, but you're at your own here."
        exit 1
    fi

    if [ ! -x /usr/bin/gcc ]; then
        echo "As a dependency to Homebrew, you need to install Xcode (available as a free download from Mac App Store or"
        echo "from http://developer.apple.com/) and Xcode's \"Command Line Tools\" (open Xcode, go to "
        echo "\"Xcode\" -> \"Preferences...\", select \"Downloads\", choose \"Components\", click \"Install\" near"
        echo "the \"Command Line Tools\" entry, wait for a while)."
        exit 1
    fi

    if [ ! "${I_HAVE_INSTALLED_CLD:+x}" ]; then
        echo "You have to manually download, build and install Chromium Compact Language Detector library from:"
        echo
        echo "http://code.google.com/p/chromium-compact-language-detector/"
        echo
        echo "When you have done that, make sure that you have libcld.0.dylib somewhere (e.g. in "
        echo "/usr/local/lib/libcld.0.dylib) and run this script again with the environment variable "
        echo "I_HAVE_INSTALLED_CLD being set as such:"
        echo
        echo "I_HAVE_INSTALLED_CLD=1 $0"
        echo
        exit 1
    fi

    brew install \
        perl --use-threads \
        graphviz --with-bindings \
        coreutils postgresql curl tidy libyaml berkeley-db4 gawk

    sudo cpan XML::Parser XML::SAX::Expat XML::LibXML XML::LibXML::Simple \
        Test::WWW::Mechanize OpenGL \
        DBD::Pg Perl::Tidy HTML::Parser \
        YAML YAML::LibYAML YAML::Syck \
        List::AllUtils List::MoreUtils \
        Readonly Readonly::XS \
        BerkeleyDB \
        GraphViz Graph

    # Absolute path because we need to use Perl from Homebrew
    sudo -n -u root -H /usr/local/bin/cpan App::cpanminus
    sudo -n -u root -H /usr/local/bin/cpanm Graph::Writer::GraphViz
    sudo -n -u root -H /usr/local/bin/cpanm HTML::Entities
    sudo -n -u root -H /usr/local/bin/cpanm version
    sudo -n -u root -H /usr/local/bin/cpanm Lingua::Stem::Snowball

else

    # assume Ubuntu
    sudo apt-get --assume-yes install \
        expat libexpat1-dev libxml2-dev \
        gawk \
        postgresql-server-dev-all postgresql-client libdb-dev libtest-www-mechanize-perl libtidy-dev \
        libopengl-perl libgraph-writer-graphviz-perl libgraphviz-perl graphviz graphviz-dev graphviz-doc libgraphviz-dev \
        libyaml-syck-perl liblist-allutils-perl liblist-moreutils-perl libreadonly-perl libreadonly-xs-perl curl \
        build-essential make gcc g++ cpanminus perl-doc liblocale-maketext-lexicon-perl openjdk-7-jdk supervisor \
        gearman libgearman-dev

    # Install CLD separately
    if [ ! "${I_HAVE_INSTALLED_CLD:+x}" ]; then     # Not installed manually?
        if [ ! -f /usr/lib/libcld.so ]; then        # Library is not installed yet?

            # Try to download and install
            CLDTEMPDIR=`mktemp -d -t cldXXXXX`
            wget -O "$CLDTEMPDIR/cld.deb" http://chromium-compact-language-detector.googlecode.com/files/compact-language-detector_0.1-1_amd64.deb
            sudo dpkg -i "$CLDTEMPDIR/cld.deb"
            rm -rf "$CLDTEMPDIR"

            if [ ! -f /usr/lib/libcld.so ]; then    # Installed?
                echo "I have tried to install CLD manually but failed."
                echo
                echo "You have to manually download, build and install Chromium Compact Language Detector library from:"
                echo
                echo "http://code.google.com/p/chromium-compact-language-detector/"
                echo
                echo "When you have done that, make sure that you have libcld.0.dylib somewhere (e.g. in "
                echo "/usr/local/lib/libcld.0.dylib) and run this script again with the environment variable "
                echo "I_HAVE_INSTALLED_CLD being set as such:"
                echo
                echo "I_HAVE_INSTALLED_CLD=1 $0"
                echo
                exit 1
            fi
        fi
    fi

fi

echo
echo "installing media cloud system dependencies"
