#!/usr/bin/python

import time

import ipdb
#import time
#import csv
import sys
import pysolr
import dateutil.parser
import collections
from collections import defaultdict
import re
import nltk
from nltk.tokenize import word_tokenize, regexp_tokenize
from nltk.stem.lancaster import LancasterStemmer
from nltk.stem.porter import PorterStemmer
import multiprocessing
from nltk.tokenize import RegexpTokenizer

from joblib import Parallel, delayed
import multiprocessing


in_memory_word_count_threshold = 0

def fetch_all( solr, fq, query, fields=None ) :
    documents = []
    num_matching_documents = solr.search( query, **{ 'fq': fq } ).hits

    start = 0
    #rows = num_matching_documents
    rows = num_matching_documents

    sys.stderr.write( " starting fetch for \n" + query )
    while (len( documents ) < num_matching_documents):
        sys.stderr.write( 'fetching {0} documents'.format( rows ) )
        sys.stderr.write( "\n" );
        results = solr.search( query, **{
                'fq': fq,
                'start': start,
                'rows': rows,
                'fl' : fields,
                })
        documents.extend( results.docs )
        start += rows

        assert len( documents ) <= num_matching_documents

    assert len( documents ) == num_matching_documents
    return documents


#tokenizer = RegexpTokenizer(r'\w+')

def tokenize( str ):
#    return filter( lambda word : word not in { '-',',','.','!' }, regexp_tokenize(str, r'\w+' ) )
    return re.split( r'[\W\']+', str ) 

def split_into_chunks( list, partitions ):
    print "starting split_into_chunks"
    partition_size = len( list ) / partitions
    chunks = [ list[start:start+partition_size] for start in xrange( 0, len(list), partition_size ) ]

    print "returning from split_into_chunks"
    return chunks

def get_frequency_counts( token_lists ):

    sentences_processed = 0
    freq = collections.Counter()

    for token_list in token_lists:
        #sentences_processed += 1
        #if sentences_processed % 10000 == 0 :
        #    print "Processed {} ".format( sentences_processed )
        freq.update( token_list )

    return freq
    
    
def non_stemmed_word_count( sentences ):
    start_time = time.time()
    non_stemmed_word_count_start_time = start_time
    print "starting  non_stemmed_word_count "
    print time.asctime()

    print 'tokenizing '

   # token_lists = Parallel(n_jobs=8, verbose=5, pre_dispatch='3*n_jobs')(delayed ( tokenize)( sentence) for sentence in sentences )

    pool = multiprocessing.Pool() 

    token_lists = pool.map( tokenize, sentences )

    pool.close()
    pool.join()

    end_time = time.time()
    print 'done tokenizing'
    print "time {}".format( str(end_time - start_time) )

    print 'chunking '
    start_time = time.time()

    chunks = split_into_chunks( token_lists, 20 )

    end_time = time.time()

    print 'done chunking '
    print "time {}".format( str(end_time - start_time) )


    print 'getting freq counts'

    start_time = time.time()
    pool =  multiprocessing.Pool() 

    freq_counts = pool.map( get_frequency_counts, chunks )

    pool.close()
    pool.join()

    pool = None

    end_time = time.time()
    print "time {}".format( str(end_time - start_time) )
    print 'done getting freq counts'

    print "summing freq_counts "
    start_time = end_time

    freq = collections.Counter()

    for freq_count in freq_counts:
        freq += freq_count

    end_time = time.time()

    print "done summing freq_counts "
    print "time {}".format( str(end_time - start_time) )

    print "Returning"
    print time.asctime()
    print "total subroution time: {} ".format( end_time - non_stemmed_word_count_start_time )
    return freq

def in_memory_word_count( sentences ):
    freq = collections.Counter()
    for sentence in sentences:
        freq.update(sentence.split())
    
    return freq

def solr_connection() :
    return pysolr.Solr('http://localhost:8983/solr/')

def get_word_counts( solr, fq, query, num_words, field='sentence' ) :
    print query

    print str(time.asctime())

    start_time = time.time()

    function_start_time = start_time
    
    results = fetch_all( solr, fq, query, 'sentence' )
    print "got " + query
    print len( results )
    print time.asctime()

    end_time = time.time()
    print "time {}".format( str(end_time - start_time) )

    start_time = end_time

    print 'converting to utf8 and lowercasing';
    sentences = [ result['sentence'].lower() for result in results ]

    results = None

    end_time = time.time()
    print "time {}".format( str(end_time - start_time) )

    start_time = end_time


    print 'calculating non_stemmed_wordcounts'
    term_counts = non_stemmed_word_count( sentences )

    if '' in term_counts:
        del term_counts['']

    print "Returned from non_stemmed_word_count"
    print time.asctime()
    end_time = time.time()
    print "time {}".format( str(end_time - start_time) )

    start_time = end_time
    print "freeing sentences "
    sentences = None
    
    end_time = time.time()
    print "time {}".format( str(end_time - start_time) )


    start_time = end_time

    print 'stemming and counting'

    stem_counts = collections.Counter()

    st = PorterStemmer()
    for term in term_counts.keys():
        #ipdb.set_trace()
        stem = st.stem_word( term )
        stem_counts[ stem ] += term_counts[ term ]


    end_time = time.time()
    print "done stemming and counting "
    print "time {}".format( str(end_time - start_time) )

    start_time = end_time

    print ' calcuating stem to term map '
    stem_to_terms = {}
    for term in term_counts.keys():
        stem = st.stem_word( term )
        if stem not in stem_to_terms:
            stem_to_terms[ stem ] = []

        stem_to_terms[stem].append( term )

    print "done calcuating stem to term map "
    print "time {}".format( str(end_time - start_time) )


    counts = stem_counts.most_common( num_words )

    ret = [ ]
    for stem, count in counts:
        if len( stem_to_terms[ stem ] ) < 2:
            term = stem_to_terms[ stem][0]
        else:
            best_count = 0
            for possible_best in stem_to_terms[ stem ] :
                if term_counts[ possible_best ] > best_count:
                    term = possible_best
                    best_count = term_counts[ possible_best ]

        ret.append( 
            { 'stem': stem, 
              'term': term,
              'count': count
              } )


    end_time  = time.time()
    print "total time {}".format( str(end_time - function_start_time) )

    return ret

def main():

    solr = solr_connection()
    fq = ' publish_date:[2013-04-01T00:00:00.000Z TO 2013-04-01T00:00:00.000Z+1MONTH]'
    query = 'sentence:mccain'

    counts = get_word_counts( solr, fq, query, 'sentence' )

    print 'printing counts'
    print counts

if __name__ == "__main__":
    main()
