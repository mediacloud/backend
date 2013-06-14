
import json
import requests
import re
import csv
import codecs
import logging

media_info = None

def mediaSource(media_id):
    '''
    Call this to get info about a particular media source that you know the id of
    '''
    global media_info
    if media_info == None:
        media_info = {}
        MEDIA_FILE = 'mediacloud/data/media_ids.csv'
        csv_reader = csv.reader(codecs.open(MEDIA_FILE, 'rU'))
        header = csv_reader.next() # skip header
        for row in csv_reader:
            m_id = str(row[0])
            media_info[m_id] = {}
            for idx, column_name in enumerate(header):
                media_info[m_id][ column_name ] = row[idx]
    return media_info[str(media_id)]

class MediaCloud(object):
    '''
    Simple client library for the nascent MediaCloud story feed API
    '''

    VERSION = "0.3"

    API_URL = "http://amanda.law.harvard.edu/admin/api/stories/"

    DEFAULT_STORY_COUNT = 25

    def __init__(self, api_user=None, api_pass=None):
        logging.basicConfig(filename='mediacloud-api.log',level=logging.DEBUG)
        self._api_user = api_user
        self._api_pass = api_pass

    def mediaSource(self, media_id):
        return mediaSource(media_id)

    def createStorySubset(self, start_date, end_date, media_id):
        '''
        Call this to create a subset of stories by date and media source.  This will return a subset id.
        Call this once, then use isStorySubsetReady to check if it is ready.
        It will take the backend system a while to generate the stream of stories for the newly created subset.
        Date format is YYYY-MM-DD
        '''
        date_format = re.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
        if not date_format.match(start_date):
            raise ValueError('start_date must be in YYYY-MM-DD')
        if not date_format.match(end_date):
            raise ValueError('start_date must be in YYYY-MM-DD')
        params = {'media_id':media_id, 'end_date':end_date, 'start_date':start_date}
        results = self._query('subset/', {'data':json.dumps(params,separators=(',',':'))} )
        return results['story_subsets_id']

    def storySubsetDetail(self, subset_id):
        '''
        '''
        return self._query('subset/'+str(subset_id), {}, 'GET')

    def isStorySubsetReady(self, subset_id):
        '''
        Checks if a story subset is complete.  This can take a while.  Returns true or false.
        Once it returns true, you can page through the stories with allProcessedInSubset
        '''
        subset_info = self.storySubsetDetail(subset_id)
        return (subset_info['ready']==1)

    def allProcessedInSubset(self,subset_id, page=1):
        '''
        Retrieve all the processed stories within a certain subset, 20 at a time
        '''
        return self._query( 'subset_processed/'+str(subset_id), { 'page':page }, 'GET' )

    def allProcessed(self, page=1):
        '''
        Return the last fully processed 20 stories (ie. with sentences pulled out)
        '''
        return self._query( 'all_processed', { 'page':page }, 'GET' )

    def _query(self, method, params={}, http_method='PUT'):
        '''
        Helper that actually makes the requests
        '''
        url = self.API_URL + method
        logging.debug("query "+url+" with "+str(params))
        r = requests.request( http_method, url, 
            params=params,
            auth=(self._api_user, self._api_pass), 
            headers={ 'Accept': 'application/json'}  
        )
        return r.json()
