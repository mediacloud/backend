
import json
import requests

class MediaCloud(object):
    '''
    Simple client library for the nascent MediaCloud story feed API
    '''

    VERSION = "0.2"

    OLD_API_URL = "http://amanda.law.harvard.edu/admin/stories/"
    API_URL = "http://amanda.law.harvard.edu/admin/api/stories/"

    DEFAULT_STORY_COUNT = 25

    def __init__(self, api_user=None, api_pass=None):
        self._api_user = api_user
        self._api_pass = api_pass
        
    def allProcessed(self, page=1):
        '''
        Return the last fully processed 20 stories (ie. with sentences pulled out)
        '''
        return self._query( 'all_processed', { 'page':page } )

    def storiesSince(self, story_id, count=DEFAULT_STORY_COUNT, fetch_raw_text=False):
        '''
        Return of list of stories with ids greater than the one specified
        '''
        return self._query('stories_query_json', 
            {'last_stories_id': story_id, 'story_count':count, 'raw_1st_download':(1 if fetch_raw_text else 0) } )
        
    def recentStories(self, story_count=DEFAULT_STORY_COUNT,  fetch_raw_text=False):
        '''
        Return of list of the most recent stories 
        '''
        return self._query('stories_query_json', 
            {'story_count':story_count, 'raw_1st_download':(1 if fetch_raw_text else 0)} )

    def storyDetail(self, story_id,  fetch_raw_text=False):
        '''
        Return the details about one story, by id
        '''
        return self._query('stories_query_json',
            {'start_stories_id':story_id, 'story_count':1, 'raw_1st_download':(1 if fetch_raw_text else 0) } )[0]
    
    def _query(self, method, params):
        '''
        Make an authenticated request to MediaCloud with the URL params passed in
        '''
        base_url = self.API_URL
        if method=='stories_query_json':
            base_url = self.OLD_API_URL
        r = requests.get( base_url + method, 
                params=params,
                auth=(self._api_user, self._api_pass), 
                headers={ 'Accept': 'application/json'}  
            )
        return r.json()
