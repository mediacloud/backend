#!/bin/bash

set -u
set -o  errexit

# Some dedicated server companies set the hostnames / domainnames of their
# virtual servers to numeric values (such as 288066). The test suite is
# then unable to access http://288066/

function hostname_help {
    echo "Please set the hostname to an alphanumeric value, e.g.:"
    echo "    export HOSTNAME=mediacloud"
    echo "    sudo hostname mediacloud"
    echo "    echo 127.0.0.1 \`hostname\` | sudo tee -a /etc/hosts"
    echo "and then try again."    
}

function domainname_help {
    echo "Please set the domainname to an alphanumeric value, e.g.:"
    echo
    echo "    sudo domainname local"
    echo "    echo 127.0.0.1 \`hostname\`.\`domainname\` | sudo tee -a /etc/hosts"
    echo
    echo "and then try again."
}

system_hostname=`hostname`
shell_hostname="$HOSTNAME"      # internal bash variable
system_domainname=`domainname`
if [[ -z "$system_hostname" || "$system_hostname" == "(none)" 
    || -z "$shell_hostname" || "$shell_hostname" == "(none)" ]]; then

    echo "Unable to determine hostname or hostname is empty."
    hostname_help
    exit 1
fi
if [[ "$system_hostname" =~ ^[0-9]+$ || "$shell_hostname" =~ ^[0-9]+$ ]] ; then
    echo "Your hostname ('$HOSTNAME') consists only of integers and thus some of the tests might fail."
    hostname_help
    exit 1
fi
if [[ -z "$system_domainname" || "$system_domainname" == "(none)" ]]; then
    echo "Unable to determine domainname or domainname is empty."
    domainname_help
    exit 1
fi
if [[ "$system_domainname" =~ ^[0-9]+$ ]] ; then
    echo "Your domainname ('$system_domainname') consists only of integers and thus some of the tests might fail."
    domainname_help
    exit 1
fi

# Run test suite
working_dir=`dirname $0`

cd $working_dir

cd ..

exec ./script/run_carton.sh exec -Ilib/ -- prove -r lib/ script/ t/
