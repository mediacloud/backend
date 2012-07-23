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

    sudo port install \
        coreutils expat p5.12-xml-parser p5.12-xml-sax-expat p5.12-xml-libxml p5.12-xml-libxml-simple \
        p5.12-libxml-perl p5.12-test-www-mechanize p5.12-opengl \
        graphviz +perl \
        p5.12-graphviz p5.12-graph \
        postgresql84 +perl \
        postgresql84-server \
        p5.12-dbd-pg +postgresql84 \
        tidy p5.12-perl-tidy p5.12-html-parser \
        libyaml p5.12-yaml p5.12-yaml-libyaml p5.12-yaml-syck \
        p5.12-list-allutils p5.12-list-moreutils \
        p5.12-readonly p5.12-readonly-xs \
        db44 p5.12-berkeleydb

    # Absolute path because we need to use Perl from MacPorts
    sudo /opt/local/bin/cpan-5.12 App::cpanminus
    if [ -x /opt/local/bin/cpanm ]; then
        CPANM=/opt/local/bin/cpanm
    elif [ -x /opt/local/libexec/perl5.12/sitebin/cpanm ]; then
        CPANM=/opt/local/libexec/perl5.12/sitebin/cpanm
    else
        echo "I have tried to install 'cpanm' (App::cpanminus) previously, but not I am unable to locate it."
        exit 1
    fi

    sudo $CPANM Graph::Writer::GraphViz
    sudo $CPANM HTML::Entities
    sudo $CPANM version
    sudo $CPANM Lingua::Stem::Snowball

else

    # assume Ubuntu
    sudo apt-get --assume-yes install \
        expat libexpat1-dev libxml2-dev \
        postgresql-server-dev-8.4 postgresql-client-8.4 libdb-dev libtest-www-mechanize-perl libtidy-dev \
        libopengl-perl libgraph-writer-graphviz-perl libgraphviz-perl graphviz graphviz-dev graphviz-doc libgraphviz-dev \
        libyaml-syck-perl liblist-allutils-perl liblist-moreutils-perl libreadonly-perl libreadonly-xs-perl \
        build-essential make gcc g++ cpanminus

fi

echo
echo "installing media cloud system dependencies"
