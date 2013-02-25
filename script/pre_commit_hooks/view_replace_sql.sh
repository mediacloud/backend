#!/bin/bash

grep -i 'CREATE VIEW' script/mediawords.sql   |  sed -e 's/CREATE VIEW //i'  |  sed -e 's/ .*//' | sed -e s'/\(.*\)/DROP VIEW IF EXISTS \1 ;/'
grep -i 'CREATE VIEW' script/mediawords.sql  -A 1

