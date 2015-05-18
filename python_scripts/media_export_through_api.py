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

local_key = '2a4cebc31101a2d3d5e60456c23ae877c2d49944068f237e1134e2c75191a2af'
local_key = '1161251f5de4f381a198eea4dc20350fd992f5eef7cb2fdc284c245ff3d4f3ca'
source_media_cloud_api_url =  'http://localhost:8000/'
dest_media_cloud_api_url = 'http://localhost:3000/'
source_api_key = 'e07cf98dd0d457351354ee520635c226acd238ecf15ec9e853346e185343bf7b'
dest_api_key = local_key

db_label =  "AWS backup crawler"

conn = mc_database.connect_to_database( db_label )
cursor = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

cursor.execute( "SELECT * from downloads where type='feed' and state in ( 'success', 'feed_error') order by downloads_id limit 10" )
feed_downloads = cursor.fetchall()

for feed_download in feed_downloads:
    download = get_download_from_api( source_media_cloud_api_url, source_api_key, feed_download['downloads_id'] )
    #print download
    #break
    raw_content = download['raw_content' ]
    del download['raw_content']

    if download[ 'state' ] == 'feed_error':
        download[ 'state' ]  = 'success'
    add_feed_download_with_api( dest_media_cloud_api_url, dest_api_key, download, raw_content )
    
