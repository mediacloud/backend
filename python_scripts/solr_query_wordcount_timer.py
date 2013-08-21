#!/usr/bin/python

import requests
import ipdb
import time
import csv
import sys
import pysolr
import dateutil.parser

def get_word_counts( solr, query, date_str, count=1000 ) :
    date = dateutil.parser.parse( date_str )
    documents = []
    
    date_str = date.isoformat() + 'Z'
    date_query = "publish_date:[{0} TO {0}+7DAYS]".format(date_str)

    sys.stderr.write( ' starting fetch for ' + query )
    sys.stderr.write( "\n");

    facet_field = "includes"

    results = solr.search( query, **{ 
            'facet':"true",
            "facet.limit":count,
            "facet.field": facet_field,
            "facet.method":"enum",
            "fq": date_query,
            })

    facets = results.facets['facet_fields']['includes']

    counts = dict(zip(facets[0::2],facets[1::2]))

    return counts

solr = pysolr.Solr('http://localhost:8983/solr/')

results = get_word_counts(solr, 'sentence:the', '2013-08-10', count=100);

print results
#print results.facets['facet_fields']['includes']

ipdb.set_trace()
