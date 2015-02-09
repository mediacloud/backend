#!/bin/bash


cmd_str="$1"
shift

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

thrift -r  --gen perl solr.thrift
thrift -r  --gen py:utf8strings   solr.thrift
