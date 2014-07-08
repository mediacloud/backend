#!/bin/bash

## These 3 lines are mandatory.
export PERLBREW_ROOT=$HOME/perl5/perlbrew
export PERLBREW_HOME=$HOME/.perlbrew
#echo source ${PERLBREW_ROOT}/etc/bashrc

unset MANPATH
source ${PERLBREW_ROOT}/etc/bashrc

# Switch to whatever version has the "mediacloud" library
perlbrew use @mediacloud

# NOTE: We filter the useless MANPATH warning message this way because there was no good way to get rid of it.
# perlbrew use will fail unless $MANPATH is set but then it generates this warning.
