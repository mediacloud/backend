#!/bin/bash
DIR=`dirname -- "$0"`

cd "$DIR"
supervisord -c supervisord.conf