#!/usr/bin/python

import requests
import ipdb
import time
import csv
import sys
import pysolr

def fetch_all( solr, query ) :
    documents = []
    num_matching_documents = solr.search( query ).hits

    start = 0
    rows = num_matching_documents

    sys.stderr.write( ' starting fetch for ' + query )
    sys.stderr.write( 'fetching {0} documents'.format( rows ) )
    while ( len( documents ) < num_matching_documents ) :
        results = solr.search( query, **{ 
                'start': start,
                'rows': rows,
               # 'fl' : 'media_id',
                })
        documents.extend( results.docs )
        start += rows

        assert len( documents ) <= num_matching_documents

    assert len( documents ) == num_matching_documents
    return documents



solr = pysolr.Solr('http://localhost:8983/solr/')

queries = [ 'sentence:obama',
            ]
file=open('out.txt','wb')

for query in queries:
   print query
   results = fetch_all( solr, query )
   print "got " + query
   print len( results )

   sentences = [ result['sentence'].encode('utf-8') for result in results ]
   file.write("\n".join( sentences))
   #file.writelines( sentences )

   #ipdb.set_trace()
   #file.writelines(str(results))
