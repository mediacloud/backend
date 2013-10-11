#!/usr/bin/python

from flask import Flask, jsonify, request
import solr_query_wordcount_timer
import ipdb

app = Flask(__name__)

solr = solr_query_wordcount_timer.solr_connection()

@app.route('/wc/')
def word_count():

    fq = request.args.getlist('fq')

    q =  request.args.get('q')

    num_words = request.args.get( 'nw' )

    if not num_words:
        num_words = 500

    print "num_words: {0} q={1} fq={2}".format( num_words, q, fq )

    key = get_key( q, fq, num_words )

    ret = fetch_from_cache( key )

    if ret:
        print "Returning from cache with key '{}'".format( key  )
        return ret
    else:
        ret = solr_query_wordcount_timer.get_word_counts_for_service( solr, fq, num_words, q )

        ret = jsonify( { 'counts': ret } )

        store_in_cache( key, ret )

        return ret

cache = {}

def get_key( q, fq, num_words ):
    return "q:{}_fq:{}_num_words:{}".format( q, fq, num_words )

def fetch_from_cache( key ) :
    if key in cache:
        return cache[ key ]
    else:
        return None

def store_in_cache( key, value ):
    cache[key] = value

@app.route('/clear_cache')
def clear_cache():
    print "Clearing cache"
    cache.clear()
    return "Cache cleared\n"

@app.route('/')
def index():
    return "Hello, World!"

if __name__ == '__main__':
    app.run(debug = False )
