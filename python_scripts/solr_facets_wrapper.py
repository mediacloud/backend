#!/usr/bin/python

import ipdb
import sys
import pysolr
import dateutil.parser
import solr_in_memory_wordcount_stemmed

def facet_query( solr, q, facet_field, fq=None, mincount=1 ):
    params = { "facet": "true", 
                               "fq": fq,
                               "fl": "media_id", 
                               "facet.mincount": mincount,
                               "indent": "true",
                               "facet.field": facet_field, 
                               "wt": "json", 
                               "rows": "1"} 
      
    if not fq:
        del params[ 'fq' ]
    
    results = solr.search( q, ** params )

    return results

def facet_query_counts( solr, q, facet_field, fq=None, mincount=1 ) :
    results = facet_query( solr, q, facet_field, fq, mincount )  

    facets = results.facets['facet_fields']['media_id']
    counts = dict( zip( facets[0::2], facets[1::2] ) )
    return counts

