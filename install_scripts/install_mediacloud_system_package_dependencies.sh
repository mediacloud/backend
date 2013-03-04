#!/bin/bash

set -u
set -o errexit

echo "installing media cloud system dependencies"
echo

if [ `uname` == 'Darwin' ]; then

    # Mac OS X

    if [ ! -x /opt/local/bin/port ]; then
        echo "You'll need MacPorts <http://www.macports.org/> to install the required packages on Mac OS X."
        echo "It might be possible to do that manually with Fink <http://www.finkproject.org/>, but you're at your own here."
        exit 1
    fi

    if [ ! -x /usr/bin/gcc ]; then
        echo "As a dependency to MacPorts, you need to install Xcode (available as a free download from Mac App Store or "
        echo "from http://developer.apple.com/) and Xcode's \"Command Line Tools\" (open Xcode, go to \"Xcode\" -> \"Preferences...\","
        echo "select \"Downloads\", choose \"Components\", click \"Install\" near the \"Command Line Tools\" entry, wait "
        echo "for a while)."
        exit 1
    fi

    brew install \
        perl --use-threads \
        graphviz --with-bindings \
        coreutils postgresql curl tidy libyaml berkeley-db4

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
        postgresql-server-dev-all postgresql-client libdb-dev libtest-www-mechanize-perl libtidy-dev \
        libopengl-perl libgraph-writer-graphviz-perl libgraphviz-perl graphviz graphviz-dev graphviz-doc libgraphviz-dev \
        libyaml-syck-perl liblist-allutils-perl liblist-moreutils-perl libreadonly-perl libreadonly-xs-perl curl \
        build-essential make gcc g++ cpanminus perl-doc liblocale-maketext-lexicon-perl

fi

echo
echo "installing media cloud system dependencies"
