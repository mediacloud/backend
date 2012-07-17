#!/bin/bash

set -u
set -o errexit

echo "installing media cloud system dependencies"
echo

if [ `uname` == 'Darwin' ]; then

    # Mac OS X
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
    sudo /opt/local/bin/cpanm Graph::Writer::GraphViz
    sudo /opt/local/bin/cpanm HTML::Entities
    sudo /opt/local/bin/cpanm version
    sudo /opt/local/bin/cpanm Lingua::Stem::Snowball

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
