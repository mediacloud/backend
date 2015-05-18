# -*- coding: utf-8 -*-

import psycopg2
import psycopg2.extras
import requests
import json

import mc_database
import mediacloud

def get_download_from_api( mc_api_url, api_key, downloads_id ):
    
    r = requests.get( mc_api_url +'/api/v2/downloads/single/' + str( downloads_id) , 
                     params = { 'key': api_key} )
    download = r.json()[0]
    return download

def add_feed_download_with_api( mc_api_url, api_key, download, raw_content ):
    r = requests.put( mc_api_url + '/api/v2/crawler/add_feed_download', 
             params={  'key': api_key }, 
             data=json.dumps( { 'download': download, 'raw_content': raw_content } ),
             headers={ 'Accept': 'application/json'} )

    return r

def main( source_media_cloud_api_url, dest_media_cloud_api_url, source_api_key, dest_api_key, db_label ):
    conn = mc_database.connect_to_database( db_label )
    cursor = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    print "fetching feed downloads from postgresql"
    cursor.execute( "SELECT downloads_id from downloads where type='feed' and state in ( 'success', 'feed_error') order by downloads_id limit 100" )
    feed_downloads = cursor.fetchall()

    feed_downloads_processed = 0

    print "exporting feed downloads with API"

    for feed_download in feed_downloads:
        download = get_download_from_api( source_media_cloud_api_url, source_api_key, feed_download['downloads_id'] )
        #print download
        #break
        raw_content = download['raw_content' ]
        del download['raw_content']

        if download[ 'state' ] == 'feed_error':
            download[ 'state' ]  = 'success'
        add_feed_download_with_api( dest_media_cloud_api_url, dest_api_key, download, raw_content )

        feed_downloads_processed+= 1

        if feed_downloads_processed % 10 == 0:
            print "Processed " + str( feed_downloads_processed ) + " downloads "
            print "last download ", feed_download

import argparse

parser = argparse.ArgumentParser(description='Export feed downloads through API.')

parser.add_argument( '--source-api-key', required=True )
parser.add_argument( '--dest-api-key', required=True )
parser.add_argument( '--source-media-cloud-api_url', required=True )
parser.add_argument( '--dest-media-cloud-api_url', required=True )
parser.add_argument( '--db-label', required=False, default=None )

args = parser.parse_args()

source_media_cloud_api_url = args.source_media_cloud_api_url
dest_media_cloud_api_url = args.dest_media_cloud_api_url
source_api_key = args.source_api_key
dest_api_key = args.dest_api_key
db_label = args.db_label

main ( source_media_cloud_api_url, dest_media_cloud_api_url, source_api_key, dest_api_key, db_label )
