import requests
import mc_config
import psycopg2
import psycopg2.extras
import time
import json
import pysolr
import sys

def py_solr_connection():
    solr = pysolr.Solr(get_solr_collection_url_prefix(), timeout=300)
    
    return solr

def get_solr_collection_url_prefix():
    config = mc_config.read_config()

    #print >> sys.stderr, config

    solr_collection_url = config['mediawords'][ 'solr_url' ][0] + '/collection1'

    return solr_collection_url

def solr_request( path, params):
    url = get_solr_collection_url_prefix() + '/' + path
    print 'url: {}'.format( url )
    params['wt'] = 'json'
    r = requests.get( url, params=params, headers = { 'Accept': 'application/json'}) 
    print 'request url '
    print r.url

    data = r.json()

    return data

def _solr_post( path, params, payload):
    url = get_solr_collection_url_prefix() + '/' + path
    print 'url: {}'.format( url )

    r = requests.post( url, data=json.dumps(payload), params=params, headers = { 'Accept': 'application/json', 'Content-type': 'application/json; charset=utf-8' } )
    print 'request url '
    print r.url

    data = r.json()

    return data

def delete_all_documents():
    _solr_post( 'update', { 'commit': 'true'}, {'delete': {'query': '*:*'}} )

def dataimport_command( command, params={}):
    params['command'] = command
    return solr_request( 'dataimport', params )

def dataimport_status():
    return dataimport_command( 'status' )

def dataimport_delta_import():
    params = {
        'commit':  'true',
        'clean':  'false',
        }

    ##Note: We're using the delta import through full import approach
    return dataimport_command( 'full-import', params )

def dataimport_full_import():
    params = {
        'commit':  'true',
        'clean':  'true',
        }

    ##Note: We're using the delta import through full import approach
    return dataimport_command( 'full-import', params )
    
def dataimport_reload_config():
    return dataimport_command( 'reload' )
