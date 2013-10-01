#!/usr/bin/python

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
from nltk.tokenize import word_tokenize
from nltk.stem.lancaster import LancasterStemmer
from nltk.stem.porter import PorterStemmer
import multiprocessing
from nltk.tokenize import RegexpTokenizer

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

def stem_sentences( sentences ):
    g = open('out_stemmed.txt','w')
    
    st = PorterStemmer()

    stemmed_sentences = []
    lines = 0
    for line in sentences:
	    sentence = word_tokenize(line)
            output = ""
	    for word in sentence:
		output += st.stem_word(word)
		s = str(output)

                output += " "
                
		g.write(s + "\n")
            
            stemmed_sentences.append( output )

            lines += 1
            if lines % 1000 == 0 :
                print "Stemmed {} ".format( lines )

    return stemmed_sentences

def tokenize( str ):
    tokenizer = RegexpTokenizer(r'\w+')
    return filter( lambda word : word not in { '-',',','.','!' }, word_tokenize( str ) )

def non_stemmed_word_count( sentences ):
    freq = collections.Counter()
    tokenizer = RegexpTokenizer(r'\w+')
    for sentence in sentences:
        freq.update( tokenize(sentence))
    
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
    results = fetch_all( solr, fq, query, 'sentence' )
    print "got " + query
    print len( results )
    
    print 'converting to utf8 and lowercasing';
    sentences = [ result['sentence'].encode('utf-8').lower() for result in results ]

    results = None

    print 'calculating non_stemmed_wordcounts'
    term_counts = non_stemmed_word_count( sentences )

    sentences = None

    st = PorterStemmer()

    print 'stemming'

    stems = [ st.stem_word(term) for term in term_counts.elements() ]

    print 'counting stemms'
    stem_counts = collections.Counter( stems )

    print ' calcuating stem to term map '
    stem_to_terms = {}
    for term in term_counts.keys():
        stem = st.stem_word( term )
        if stem not in stem_to_terms:
            stem_to_terms[ stem ] = []

        stem_to_terms[stem].append( term )

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
    
    print ret

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
