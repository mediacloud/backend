#!/usr/bin/python

import ipdb
#import time
import csv
import sys
import pysolr
import dateutil.parser
import copy
import pickle
from collections import Counter
import re

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
    common_fq_params = ['field_type:ss', 'publish_date:[2012-01-01T00:00:00Z TO NOW]', 'sentence:"illegal immigrant" OR sentence:"illegal immigrants"']

    join_params = map ( lambda param: '-{!join from=stories_id to=stories_id}' + param[1:] if param.startswith('-') else '{!join from=stories_id to=stories_id}' + param,
          query_specific_fq_params )
    
    fq_params = common_fq_params + join_params

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

def doc_is_story_in_range( doc ):
    return doc['field_type'] == 'st' and doc['publish_date'] >= '2012-01-01T00:00:00Z'

def doc_is_sentence_in_range( doc ):
    return doc['field_type'] == 'ss' and doc['publish_date'] >= '2012-01-01T00:00:00Z'

def doc_matches_solr_query( doc, query ) :
    invert_result = False

    if '-' == query[0]:
        invert_result = True
        query = query[1:]

    str_tmp = query.split(":")
    field = str_tmp[0]
    clause = str_tmp[1]

    assert clause[0] != '['

    regex_clause = "\\b{0}\\b".format( clause )

   # ipdb.set_trace()
   # ret = doc[ field ].lower().find(clause.lower() ) != -1

    ret = re.search( regex_clause, doc[field], re.IGNORECASE )

    if invert_result:
        ret = not ret

    return ret        

def count_by_month( docs ) :
    dates = [ doc['publish_date'] for doc in docs ]
    trunc_dates = [ date[:7]  for date in dates ]
    return Counter( trunc_dates )
    
def get_story_docs_for_query( docs, query_specific_fq_params):
    story_docs = filter ( doc_is_story_in_range, docs )

    query_docs = story_docs

    assert len( query_specific_fq_params ) > 0

    for query in query_specific_fq_params:
        query_docs = filter( lambda doc: doc_matches_solr_query( doc, query), query_docs )

    return query_docs

def get_sentence_docs_for_query( docs, query_specific_fq_params):
    sentence_docs = filter ( doc_is_sentence_in_range, docs )

    query_docs = sentence_docs

    assert len( query_specific_fq_params ) > 0

    query_specific_fq_params = copy.deepcopy( query_specific_fq_params )
    
    for query in query_specific_fq_params:
        query = query.replace('title:', 'sentence:' )
        query_docs = filter( lambda doc: doc_matches_solr_query( doc, query), query_docs )

    return query_docs

def get_set_1_counts( docs,  query_specific_fq_params ):

    query_docs = get_story_docs_for_query( docs, query_specific_fq_params )

    counts = count_by_month( query_docs )

    return counts
            
def get_stories_ids_from_docs( docs ) :
    return set( [ doc[ 'stories_id' ] for doc in docs ] )

def get_sentences_with_stories_ids( docs, stories_id) :
    return filter( lambda doc: ( doc[ 'stories_id'] in stories_id ) and ( doc[ 'field_type' ] == 'ss' ), docs )

def get_stories_with_stories_ids( docs, stories_id) :

    return filter( lambda doc: ( doc[ 'stories_id'] in stories_id ) and ( doc[ 'field_type' ] == 'st' ), docs )

def get_illegal_immigrant_sentences( docs ):  
    sentences = docs
    regex1 = re.compile( "\\billegal[\\b\\W\"]+immigrant\\b", re.IGNORECASE )
    regex2 = re.compile( "\\billegal[\\b\\W\"]+immigrants\\b", re.IGNORECASE )

    matching_sentences = filter( lambda s: regex1.search(s['sentence']) or 
                                 regex2.search(s['sentence']), sentences )

    return matching_sentences

def get_illegal_immigrant_sentences_from_story_docs( docs, story_docs ):
    stories_id = get_stories_ids_from_docs( story_docs )

    sentences = get_sentences_with_stories_ids( docs, stories_id)

    matching_sentences = get_illegal_immigrant_sentences( sentences )

    return matching_sentences
    
def get_set_2_counts( docs, query_specific_fq_params ) :
    story_docs =  get_story_docs_for_query( docs, query_specific_fq_params )

    matching_sentences = get_illegal_immigrant_sentences_from_story_docs( docs, story_docs )

    counts = count_by_month( matching_sentences )

    return counts

def get_ap_byline_docs ( docs ) :
    associated_press_regex = re.compile("associated[\\b\\W\"]+press", re.IGNORECASE )
    ap_regex = re.compile("\\bap\\b", re.IGNORECASE )

    ap_docs = filter( lambda doc: doc['field_type'] == 'ss' and ( ap_regex.search( doc[ 'sentence'] ) or 
                      associated_press_regex.search( doc[ 'sentence' ] ) )
                      and doc[ 'sentence_number'] <= 3, docs )

    return ap_docs

def get_ap_byline_stories_ids( docs ) :
    ap_docs = get_ap_byline_docs( docs )
    return get_stories_ids_from_docs( ap_docs )

def get_set_3_docs( docs, query_specific_fq_params ) :
    ap_stories_ids = get_ap_byline_stories_ids( docs )
    ap_story_docs = get_stories_with_stories_ids( docs, ap_stories_ids )
    query_docs = get_story_docs_for_query( ap_story_docs, query_specific_fq_params )

    return query_docs

def get_ap_doc_counts( docs, query_specific_fq_params ) :
    ap_stories_ids = get_ap_byline_stories_ids( docs )
    ap_story_docs = get_stories_with_stories_ids( docs, ap_stories_ids )
    counts = count_by_month ( ap_story_docs )
    return counts

def get_set_3_counts ( docs, query_specific_fq_params ) :
    query_docs = get_set_3_docs( docs, query_specific_fq_params )
    
    counts = count_by_month( query_docs )

    return counts

def get_set_4_counts ( docs, query_specific_fq_params ) :
    story_docs = get_set_3_docs( docs, query_specific_fq_params )
    matching_sentences = get_illegal_immigrant_sentences_from_story_docs( docs, story_docs )

    counts = count_by_month( matching_sentences )

    return counts

def get_set_5_counts ( docs, query_specific_fq_params ) :
    query_docs = get_sentence_docs_for_query( docs, query_specific_fq_params )

    counts = count_by_month( query_docs )

    return counts

def get_set_6_counts( docs, query_specific_fq_params ) :
    ap_stories_ids = get_ap_byline_stories_ids( docs )
    ap_sentence_docs = get_sentences_with_stories_ids( docs, ap_stories_ids )
    query_docs = get_sentence_docs_for_query( ap_sentence_docs, query_specific_fq_params )

    counts = count_by_month( query_docs )

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

    docs = pickle.load( open( "docs.p", "rb" ) )


    functions_and_files =  [
        ( get_set_1_counts, '/tmp/immigrant_output/set1.csv'),
        ( get_set_2_counts, '/tmp/immigrant_output/set2.csv'),
        ( get_set_3_counts, '/tmp/immigrant_output/set3.csv'),
        ( get_set_4_counts, '/tmp/immigrant_output/set4.csv'),
        ( get_set_5_counts, '/tmp/immigrant_output/set5.csv'),
        ( get_set_6_counts, '/tmp/immigrant_output/set6.csv'),
        ]

    for func, filename in functions_and_files :
        for query_specific_filter in query_specific_filters:
            counts =  func( docs, query_specific_filter )

            for date in counts.keys():
                trunc_date = date.replace( '-01T00:00:00Z', '')
                counts[ trunc_date ] = counts.pop( date )

            #counts['query'] = str(  query_specific_filter )
            results[ str( query_specific_filter ) ] = counts


        row_titles = sorted( reduce ( lambda x,y : x.union(y) , map( lambda result: set( result.keys() ) , results.values() ) ) )

        row_titles.insert(0, 'query')

        for query in results.keys():
            results[query]['query'] = query

        with open(filename, 'wb') as csvfile:
            samplewriter = csv.DictWriter(csvfile, row_titles, restval=0 )
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

