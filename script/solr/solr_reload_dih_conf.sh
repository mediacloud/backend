#!/bin/bash

set -u
set -o errexit

curl 'http://localhost:8983/solr/collection1/dataimport?command=reload'


