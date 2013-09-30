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


def in_memory_word_count( stemmed_sentences ):
    freq = collections.Counter()
    for stemmed_sentence in stemmed_sentences:
        freq.update(stemmed_sentence.split())
    
    return freq

def solr_connection() :
    return pysolr.Solr('http://localhost:8983/solr/')

def get_word_counts( solr, fq, query, num_words, field='sentence' ) :
    print query
    results = fetch_all( solr, fq, query, 'sentence' )
    print "got " + query
    print len( results )
    
    print 'converting in utf8';
    sentences = [ result['sentence'].encode('utf-8') for result in results ]

    results = None

    print 'stemming';

    stemmed_sentences = stem_sentences( sentences )

    print 'counting'
    counts = in_memory_word_count( stemmed_sentences )
    
    return counts.most_common( num_words )
    

def main():

    solr = solr_connection()
    fq = ' publish_date:[2013-04-01T00:00:00.000Z TO 2013-04-01T00:00:00.000Z+1MONTH]'
    query = 'sentence:mccain'

    counts = get_word_counts( solr, fq, query, 'sentence' )

    print 'printing counts'
    print counts

if __name__ == "__main__":
    main()
