#!/usr/bin/python

import ipdb
#import time
#import csv
import sys
import pysolr
import dateutil.parser

in_memory_word_count_threshold = -1

def get_word_counts( solr, query, date_str, num_words=1000 ) :
    documents = []

    fq = get_fq( query )

    return _get_word_counts_impl( solr, fq, num_words )

def _get_word_counts_impl( solr, fq, num_words ):

    num_words = max ( num_words, 5000 )

    matching_documents = solr.search( '*:*', **{ 'fq': fq } ).hits

    print "{0} matching documents ".format( matching_documents )

    if (matching_documents < in_memory_word_count_threshold) and (in_memory_word_count_threshold > 0):
        print in_memory_word_count_threshold
        return in_memory_word_count(  solr, fq, num_words )
    else:
        return in_solr_word_count( solr, fq, num_words )

def in_solr_word_count( solr, fq, num_words ):
    facet_field = "includes"

    query_params = { 
            'facet':"true",
            "facet.limit": num_words,
            "facet.field": facet_field,
            "facet.method":"enum",
            "fq": fq,
            }

    #query_params['fq'] = " AND ".join( query_params['fq'] )

    results = solr.search( '*:*', ** query_params)

    #ipdb.set_trace()

    facets = results.facets['facet_fields']['includes']

    counts = dict(zip(facets[0::2],facets[1::2]))

    return counts
    

def in_memory_word_count( solr, fq, num_words ):
    raise Exception( 'unimplemented' )

def get_fq(  query ) :
    start_date = dateutil.parser.parse( query['start_date'] )
    end_date = dateutil.parser.parse( query['end_date'] )

    date_str_start = start_date.isoformat() + 'Z'
    date_str_end   = end_date.isoformat() + 'Z'

    if query['start_date'] == query['end_date']:
        date_query = "publish_date:[{0} TO {1}+7DAYS]".format(date_str_start, date_str_end)
    else:
        date_query = "publish_date:[{0} TO {1}]".format(date_str_start, date_str_end)

    media_sets_ids = query[ 'media_sets_ids' ]

    media_sets_query = 'media_sets_id:({0})'.format( " OR ".join([ "{:d}".format(id) for id in media_sets_ids ]) )
    
    #sys.stderr.write( media_sets_query )
    #sys.stderr.write( date_query )

    ret =  [date_query, media_sets_query]

    return ret

def counts_to_db_style( counts ) :
    ret = []
    total_words = sum( counts.values() )

    total_words = max( total_words, 1 )
    
    stem_count_factor = 1

    for word,count in counts.iteritems() :
        ret.append( { 'term': word,
                      'stem_count': float(count)/float(total_words),
                      'raw_stem_count': count,
                      'total_words': total_words,
                      'stem_count_factor': stem_count_factor,
                      }
                    )

    return ret
                      

def solr_connection() :
    return pysolr.Solr('http://localhost:8983/solr/')

def main():

    solr = solr_connection()
    fq = None
    
    #publish_date:[2013-09-16T00:00:00Z TO 2013-09-16T00:00:00Z+7DAYS] AND media_sets_id:(5)
    fq = 'publish_date:[2013-09-16T00:00:00Z TO *]'

    counts = _get_word_counts_impl( solr, fq, 1000 )
    print counts


if __name__ == "__main__":
    main()
