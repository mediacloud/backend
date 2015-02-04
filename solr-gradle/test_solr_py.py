#!/usr/bin/python

import solr
import pdb
from collections import Counter

def get_tf_counter ( field, hash_value ) :
    counts = response.termVectors.values()[0]['includes']
    
    c = Counter()
    
    for word in counts.keys():
        c[word] = int(counts[word]['tf'])

    return c

s = solr.Solr('http://localhost:8983/solr')

#response = s.select('*:*')
#print response

#pdb.set_trace()

field_name = 'includes'

tvrh = solr.SearchHandler( s, '/tvrh' )
response =   tvrh.__call__(q='*:*', tv_tf='true', tv_fl=field_name, fl='none', rows=1000)

for x in xrange ( 0, 1000) :
    print x
    tv = response.termVectors
    #del tv['uniqueKeyFieldName']


    response = response.next_batch()

    #print sum( [ get_tf_counter (  field_name, value) for value in  response.termVectors.values() ], Counter() )

