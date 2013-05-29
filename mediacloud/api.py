
import json
import urllib
import urllib2

class MediaCloud(object):
    '''
    Simple client library for the nascent MediaCloud story feed API
    '''

    VERSION = "0.1"

    API_URL = "http://amanda.law.harvard.edu/admin/stories/"

    DEFAULT_STORY_COUNT = 25

    def __init__(self, api_user=None, api_pass=None, debug_mode=False):
        '''
        Constructor
        '''
        self._api_user = api_user
        self._api_pass = api_pass
        self._debug_mode = debug_mode
        
    def storiesSince(self, story_id, count=DEFAULT_STORY_COUNT, fetch_raw_text=False):
        '''
        Return of list of stories with ids greater than the one specified
        '''
        if(self._debug_mode):
            f = open('mediacloud/test/fixtures/stories_15_since_'+str(story_id)+'.json','r');
            content = f.read()
            return self._parseJsonResults(content)
        return self._queryJson('stories_query_json', {'last_stories_id': story_id, 'story_count':count, 'raw_1st_download':fetch_raw_text} )
        
    def recentStories(self, story_count=DEFAULT_STORY_COUNT,  fetch_raw_text=False):
        '''
        Return of list of stories 
        '''
        if(self._debug_mode):
            f = open('mediacloud/test/fixtures/stories_30_within_last_day.json','r');
            content = f.read()
            return self._parseJsonResults(content)
        return self._queryJson('stories_query_json', {'story_count': story_count, 'raw_1st_download':fetch_raw_text} )

    def storyDetail(self, story_id,  fetch_raw_text=False):
        '''
        Return the details about one story, by id
        '''
        if(self._debug_mode):
            f = open('mediacloud/test/fixtures/story_'+str(story_id)+'.json','r');
            content = f.read()
            return self._parseJsonResults(content)[0]
        return self._queryJson('stories_query_json', {'start_stories_id': story_id, 'story_count': 1, 'raw_1st_download':fetch_raw_text} )[0]
  
    def _queryJson(self, method, params):
        '''
        Call this to make a JSON query to the MC server and return a python object 
        with results
        '''
        if params['raw_1st_download']==True:
            params['raw_1st_download'] = 1
        else:
            params['raw_1st_download'] = 0
        return self._parseJsonResults( self._query(method, params) )
  
    def _query(self, method, params):
        '''
        Make an authenticated request to MediaCloud with the URL params passed in
        '''
        auth_handler = urllib2.HTTPBasicAuthHandler()
        uri = self.API_URL + method
        auth_handler.add_password(realm='Media Cloud Admin',
                    uri= uri,
                    user= self._api_user,
                    passwd= self._api_pass)
        opener = urllib2.build_opener(auth_handler)
        urllib2.install_opener(opener)
        url_handle = urllib2.urlopen(uri, urllib.urlencode(params))
        #print uri + "?" + urllib.urlencode(params)
        return url_handle.read()
  
    def _parseJsonResults(self, json_text):
        '''
        Take in raw json text and return a python object
        '''
        story_list = json.loads(json_text)
        return story_list
