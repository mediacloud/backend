#!/bin/sh
set -u
set -o  errexit

echo "installing media cloud system dependencies"
echo

sudo apt-get --assume-yes install  expat postgresql-server-dev-8.4 postgresql-client-8.4 libexpat1-dev libxml2-dev libdb-dev libtest-www-mechanize-perl libtidy-dev  libopengl-perl libgraph-writer-graphviz-perl libgraphviz-perl graphviz graphviz-dev graphviz-doc libgraphviz-dev libyaml-syck-perl liblist-allutils-perl liblist-moreutils-perl libreadonly-perl  libreadonly-xs-perl build-essential make gcc g++ cpanminus

echo
echo "installing media cloud system dependencies"