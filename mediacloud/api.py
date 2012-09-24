
import json
import urllib
import urllib2

class MediaCloud(object):
    '''
    Simple client library for the nascent MediaCloud story feed API
    '''

    VERSION = "0.0"

    API_URL = "http://amanda.law.harvard.edu/admin/stories/stories_query_json"

    DEFAULT_STORY_COUNT = 25

    def __init__(self, api_user=None, api_pass=None, debug_mode=False):
        '''
        Constructor
        '''
        self._api_user = api_user
        self._api_pass = api_pass
        self._debug_mode = debug_mode
        
    def storiesSince(self, story_id, count=DEFAULT_STORY_COUNT):
        '''
        Return of list of stories with ids greater than the one specified
        '''
        if(self._debug_mode):
            f = open('mediacloud/test/fixtures/stories_15_since_88848861.json','r');
            content = f.read()
            return self._parseJsonResults(content)
        return self._queryJson( {'last_stories_id': story_id} )
        
    def recentStories(self, story_count=DEFAULT_STORY_COUNT):
        '''
        Return of list of stories 
        '''
        if(self._debug_mode):
            f = open('mediacloud/test/fixtures/stories_30_within_last_day.json','r');
            content = f.read()
            return self._parseJsonResults(content)
        return self._queryJson( {'story_count': story_count} )

    def storyDetail(self, story_id):
        '''
        Return the details about one story, by id
        '''
        if(self._debug_mode):
            f = open('mediacloud/test/fixtures/story_88848861.json','r');
            content = f.read()
            return self._parseJsonResults(content)[0]
        return self._queryJson( {'start_stories_id': story_id, 'story_count': 1} )[0]
  
    def _queryJson(self, params):
        '''
        Call this to make a JSON query to the MC server and return a python object 
        with results
        '''
        return self._parseJsonResults( self._query(params) )
  
    def _query(self, params):
        '''
        Make an authenticated request to MediaCloud with the URL params passed in
        '''
        auth_handler = urllib2.HTTPBasicAuthHandler()
        auth_handler.add_password(realm='Media Cloud Admin',
                    uri= self.API_URL,
                    user= self._api_user,
                    passwd= self._api_pass)
        opener = urllib2.build_opener(auth_handler)
        urllib2.install_opener(opener)
        url_handle = urllib2.urlopen(self.API_URL, urllib.urlencode(params))
        return url_handle.read()
  
    def _parseJsonResults(self, json_text):
        '''
        Take in raw json text and return a python object
        '''
        story_list = json.loads(json_text)
        return story_list
