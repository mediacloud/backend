#!/bin/bash


/usr/local/bin/supervisorctl \
    --configuration `dirname "$0"`/supervisord.conf \
    --serverurl http://localhost:8398 \
    --username supervisord \
    --password qHujfp7n4J \
    $*
