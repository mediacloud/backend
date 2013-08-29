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

queries = [ '*:*',
            ]

for query in queries:
   print query
   results = fetch_all( solr, query )
   print "got " + query
   print results

      

