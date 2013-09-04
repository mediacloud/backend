#!/usr/bin/python

import ipdb
#import time
import csv
import sys
import pysolr
import dateutil.parser
import copy
import pickle

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
    return pysolr.Solr('http://localhost:8983/solr/', timeout=3600)

def query_top25msm_for_range_title_only( solr, query_specific_fq_params ):
    common_fq_params = ['field_type:st', 'publish_date:[2012-01-01T00:00:00Z TO NOW]']
    fq_params = common_fq_params + query_specific_fq_params

    print fq_params

    result = solr.search( join_query, **{
            'facet':"true",
            'facet.range.start':'2012-01-01T00:00:00Z',
            'facet.range':'publish_date',
            'facet.range.end':['2013-08-31T00:00:00Z','2013-08-31T00:00:00Z'],
            'facet.range.gap':'+1MONTH',
            'fq': fq_params,
            })

    facet_counts = result.facets['facet_ranges']['publish_date']['counts']

    counts = dict(zip(facet_counts[0::2],facet_counts[1::2]))
    return counts

def get_stories_ids_for_query( solr, query_specific_fq_params ):
    common_fq_params = ['field_type:st', 'publish_date:[2012-01-01T00:00:00Z TO NOW]']
    fq_params = common_fq_params + query_specific_fq_params

    print fq_params

    rows = 100000

    result = solr.search( join_query, **{
            # 'facet':"true",
            # 'facet.range.start':'2012-01-01T00:00:00Z',
            # 'facet.range':'publish_date',
            # 'facet.range.end':['NOW','NOW'],
            # 'facet.range.gap':'+1MONTH',
            'fq': fq_params,
            'fl': 'stories_id',
            'rows': rows
            })

    assert result.hits <= rows

    stories_ids = set([ doc['stories_id'] for doc in result.docs ])

    return stories_ids


def query_top25msm_for_range_body( solr, query_specific_fq_params ):
    common_fq_params = ['field_type:ss', 'publish_date:[2012-01-01T00:00:00Z TO NOW]', "sentence:'illegal immigrant'"]

    join_params = [ '{!join from=stories_id to=stories_id}' + param for param in query_specific_fq_params ]
    
    fq_params = common_fq_params + join_params

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

def get_stories_ids( solr, query_specific_filters ) :
    print "start get_stories_ids"

    fetch_queries = copy.deepcopy(query_specific_filters)

    fetch_queries.extend([ map( lambda str: str.replace( "title:", "sentence:" ), query ) for query in fetch_queries ])
    stories_ids = set()
    for fetch_query  in fetch_queries:
        stories_ids_for_query = get_stories_ids_for_query( solr, fetch_query )
        stories_ids |= stories_ids_for_query

    print "got {0} stories_id's".format( len( stories_ids) )

    return stories_ids

def fetch_from_stories_ids( solr, stories_ids ) :

    rows = 100000

    docs = []

    for stories_id in sorted(stories_ids):
        query = "stories_id:{0}".format( stories_id )
        result = solr.search( query, **{
                'rows': rows
            })

        assert result.hits < rows

        docs.extend(result.docs)

    return docs


def download_and_pickle( solr, query_specific_filters ):
    stories_ids = get_stories_ids( solr, query_specific_filters ) 

    print "got stories_ids"

    docs = fetch_from_stories_ids( solr, stories_ids )

    for doc in docs:
        doc['media_sets_id'] = [ 1 ]
        del doc['_version_']

    pickle.dump( docs, open("docs.p", "wb" ) )

def unpickle_and_upload( solr ) :
    docs = pickle.load( open( "docs.p", "rb" ) )

    print "pickle load COMPLETE"

    for doc in docs:
        del doc['_version_']

    solr.add( docs )



def main():
    solr = solr_connection()

    #results = query_top25msm_for_range_body( solr, [ '{!join from=stories_id to=stories_id}title:immigrants' ] )
    #ipdb.set_trace()

    #ipdb.set_trace()

    query_specific_filters = [
        [  'title:immigrants'  ],
        [  '-title:illegal',  'title:immigrants' ],
        [  'title:illegals'  ],
        [  'title:aliens' , 'title:illegal'],
        ]

    results = {}

    #download_and_pickle( solr, query_specific_filters )

   # unpickle_and_upload( solr )

    #exit()

    for query_specific_filter in query_specific_filters:
        counts = query_top25msm_for_range_title_only( solr, query_specific_filter )
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

OLD_SCHEMA = False

if OLD_SCHEMA:
    join_query = '{!join from=media_id_inner to=media_id}media_sets_id:1'
else:
    join_query = '*:*'


if __name__ == "__main__":
    main()

