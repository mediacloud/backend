#!/bin/bash

## These 3 lines are mandatory.
export PERLBREW_ROOT=$HOME/perl5/perlbrew
export PERLBREW_HOME=$HOME/.perlbrew
#echo source ${PERLBREW_ROOT}/etc/bashrc

unset MANPATH
source ${PERLBREW_ROOT}/etc/bashrc

#if [[ -z "$PERLBREW_BASHRD_VERSION" ]]
# then
#   echo "if branch taken"
#   source ~/perl5/perlbrew/etc/bashrc
#fi

#Switch to the right version and filter useless message. 

perlbrew use perl-5.16.3@mediacloud   2> >(grep -v 'manpath: warning: $MANPATH set, ignoring /etc/manpath.config')
if [ $? -ne 0 ]; then
    echo "Unable to run 'perlbrew use perl-5.16.3@mediacloud'"
    exit 1
fi

# NOTE: We filter the useless MANPATH warning message this way because there was no good way to get rid of it.
# perlbrew use will fail unless $MANPATH is set but then it generates this warning.

