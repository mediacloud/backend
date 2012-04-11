#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

source ./script/set_perl_brew_environment.sh

carton install --deployment || echo "initial carton run "
carton install --deployment
carton install foreign_modules/YAML-Syck-1.20.tar.gz || echo " Yaml locally installed"
echo "starting install of carton within carton"
carton install foreign_modules/carton-v0.9.4.tar.gz || carton install foreign_modules/carton-v0.9.4.tar.gz  || echo " carton installed"
echo "Successfully installed Perl and modules for MediaCloud"
