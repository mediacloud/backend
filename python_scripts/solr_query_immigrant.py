#!/usr/bin/python

import ipdb
#import time
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

def counts_to_db_style( counts ) :
    ret = []
    total_words = sum( counts.values() )

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

def query_top25msm_for_range( solr, query_specific_fq_params ):
    common_fq_params = ['field_type:st', 'publish_date:[2012-01-01T00:00:00Z TO NOW]']
    fq_params = common_fq_params + query_specific_fq_params

    print fq_params

    result = solr.search( join_query, **{
            'facet':"true",
            'facet.range.start':'2012-01-01T00:00:00Z',
            'facet.range':'publish_date',
            'facet.range.end':['NOW','NOW'],
            'facet.range.gap':'+1MONTH',
            'fq': fq_params,
            })

    facet_counts = result.facets['facet_ranges']['publish_date']['counts']

    counts = dict(zip(facet_counts[0::2],facet_counts[1::2]))
    return counts

solr = solr_connection()
join_query = '{!join from=media_id_inner to=media_id}media_sets_id:1'

#ipdb.set_trace()

query_specific_filters = [
    [  '-title:illegal',  'title:immigrants' ],
    [  'title:immigrants'  ],
    [  'title:illegals'  ],
    [  'title:alien' , 'title:illegal'],
    ]

results = {}
for query_specific_filter in query_specific_filters:
    counts = query_top25msm_for_range( solr, query_specific_filter )
    #counts['query'] = str(  query_specific_filter )
    results[ str( query_specific_filter ) ] = counts

row_titles = sorted(results.values()[0].keys())
row_titles.insert(0, 'query')

for query in results.keys():
    results[query]['query'] = query

with open("/tmp/sample.csv", 'wb') as csvfile:
    samplewriter = csv.DictWriter(csvfile, row_titles )
    samplewriter.writeheader()
    samplewriter.writerows(results.values())
    
#print results


