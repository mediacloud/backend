#!/bin/bash

source ./script/set_perl_brew_environment.sh
cpanm -L local Module::Install
cpanm -L local Gearman::JobScheduler

