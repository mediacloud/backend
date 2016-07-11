#!/usr/bin/env python

import solr

s = solr.Solr('http://localhost:8983/solr')

field_name = 'includes'

tvrh = solr.SearchHandler(s, '/tvrh')
response = tvrh.__call__(q='*:*', tv_tf='true', tv_fl=field_name, fl='none', rows=1000)

for x in xrange(0, 1000):
    print x
    tv = response.termVectors
    response = response.next_batch()
