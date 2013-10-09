#!/bin/bash

source ./script/set_perl_brew_environment.sh
cpanm -L local Module::Install
cpanm -L local git://github.com/pypt/p5-Gearman-JobScheduler.git@0.07
