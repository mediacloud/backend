import re, logging, json, urllib, datetime, sys
from collections import namedtuple
import xml.etree.ElementTree, requests
import mediacloud

class MediaCloud(object):
    '''
    Simple client library for the MediaCloud API v2
    '''

    V2_API_URL = "https://api.mediacloud.org/api/v2/"

    SORT_PUBLISH_DATE_ASC = "publish_date_asc"
    SORT_PUBLISH_DATE_DESC = "publish_date_desc"
    SORT_RANDOM = "random"

    SENTENCE_PUBLISH_DATE_FORMAT = "%Y-%m-%d %H:%M:%S" # use with datetime.datetime.strptime

    def __init__(self, auth_token=None):
        self._logger = logging.getLogger('mediacloud-api')
        self.setAuthToken(auth_token)

    def setAuthToken(self, auth_token):
        '''
        Specify the auth_token to use for all future requests
        '''
        self._auth_token = auth_token
        
    def userAuthToken(self,username,password):
        '''
        Get a auth_token for future requests to use
        '''
        self._logger.debug("Requesting new auth token for "+username)
        response = self._queryForJson(self.V2_API_URL+'auth/single/',
            {'username':username, 'password':password})
        response = response[0]
        if response['result']=='found':
            self._logger.debug(" new token is "+response['token'])
            return response['token']
        else:
            self._logger.warn("AuthToken request for "+username+" failed!")
            raise Exception(response['result'])

    def media(self, media_id):
        '''
        Details about one media source
        '''
        return self._queryForJson(self.V2_API_URL+'media/single/'+str(media_id))[0]

    def mediaList(self, last_media_id=0, rows=20, name_like=None):
        '''
        Page through all media sources
        '''
        params = {'last_media_id':last_media_id, 'rows':rows}
        if name_like is not None:
            params['name'] = name_like
        return self._queryForJson(self.V2_API_URL+'media/list', 
                params)

    def mediaSet(self, media_sets_id):
        '''
        Details about one media set (a collection of media sources)
        '''
        return self._queryForJson(self.V2_API_URL+'media_sets/single/'+str(media_sets_id))[0]

    def mediaSetList(self, last_media_sets_id=0, rows=20):
        '''
        Page through all media sets
        '''
        return self._queryForJson(self.V2_API_URL+'media_sets/list',
                {'last_media_sets_id':last_media_sets_id, 'rows':rows})

    def feed(self, feeds_id):
        '''
        Details about one feed
        '''
        return self._queryForJson(self.V2_API_URL+'feeds/single/'+str(feeds_id))[0]

    def feedList(self, media_id, last_feeds_id=0, rows=20):
        '''
        Page through all the feeds of one media source
        '''
        return self._queryForJson(self.V2_API_URL+'feeds/list', 
            { 'media_id':media_id, 'last_feeds_id':last_feeds_id, 'rows':rows} )

    def dashboard(self, dashboards_id, nested_data=True):
        '''
        Details about one dashboard (a collection of media sets)
        '''
        return self._queryForJson(self.V2_API_URL+'dashboards/single/'+str(dashboards_id),
            {'nested_data': 1 if nested_data else 0})[0]

    def dashboardList(self, last_dashboards_id=0, rows=20, nested_data=True):
        '''
        Page through all the dashboards
        '''
        return self._queryForJson(self.V2_API_URL+'dashboards/list', 
                {'last_dashboards_id':last_dashboards_id, 'rows':rows, 'nested_data': 1 if nested_data else 0})

    def story(self, stories_id, raw_1st_download=False, corenlp=False):
        '''
        Details about one story
        '''
        return self._queryForJson(self.V2_API_URL+'stories/single/'+str(stories_id),
                {'raw_1st_download': 1 if raw_1st_download else 0, 'corenlp': 1 if corenlp else 0} )[0]

    def storyList(self, solr_query='', solr_filter='', last_processed_stories_id=0, rows=20, raw_1st_download=False, corenlp=False):
        '''
        Search for stories and page through results
        '''
        return self._queryForJson(self.V2_API_URL+'stories/list',
                {'q': solr_query,
                 'fq': solr_filter,
                 'last_processed_stories_id': last_processed_stories_id,
                 'rows': rows,
                 'raw_1st_download': 1 if raw_1st_download else 0, 
                 'corenlp': 1 if corenlp else 0
                }) 

    def sentenceList(self, solr_query, solr_filter='', start=0, rows=1000, sort=SORT_PUBLISH_DATE_ASC):
        '''
        Search for sentences and page through results
        '''
        return self._queryForJson(self.V2_API_URL+'sentences/list',
                {'q': solr_query,
                 'fq': solr_filter,
                 'start': start,
                 'rows': rows,
                 'sort': sort
                }) 

    def sentenceCount(self, solr_query, solr_filter=' ',split=False,split_start_date=None,split_end_date=None,split_daily=False):
        params = {'q':solr_query, 'fq':solr_filter}
        params['split'] = 1 if split is True else 0
        params['split_daily'] = 1 if split_daily is True else 0
        if split is True:
            datetime.datetime.strptime(split_start_date, '%Y-%m-%d')    #will throw a ValueError if invalid
            datetime.datetime.strptime(split_end_date, '%Y-%m-%d')    #will throw a ValueError if invalid
            params['split_start_date'] = split_start_date
            params['split_end_date'] = split_end_date
        return self._queryForJson(self.V2_API_URL+'sentences/count', params)

    def wordCount(self, solr_query, solr_filter=''):
        return self._queryForJson(self.V2_API_URL+'wc/list',
                {'q': solr_query,
                 'fq': solr_filter
                })

    def tag(self, tags_id):
        '''
        Details about one tag
        '''
        return self._queryForJson(self.V2_API_URL+'tags/single/'+str(tags_id))[0]

    def tagList(self, tag_sets_id, last_tags_id=0, rows=20):
        '''
        List all the tags in one tag set
        '''
        return self._queryForJson(self.V2_API_URL+'tags/list',
            { 'tag_sets_id':tag_sets_id, 'last_tags_id': last_tags_id, 'rows':rows })

    def tagSet(self, tag_sets_id):
        '''
        Details about one tag set
        '''
        return self._queryForJson(self.V2_API_URL+'tag_sets/single/'+str(tag_sets_id))[0]

    def tagSetList(self, last_tag_sets_id=0, rows=20):
        '''
        List all the tag sets
        '''
        return self._queryForJson(self.V2_API_URL+'tag_sets/list',
            { 'last_tag_sets_id': last_tag_sets_id, 'rows':rows })

    def _queryForJson(self, url, params={}, http_method='GET'):
        '''
        Helper that returns queries to the API as real objects
        '''
        response = self._query(url, params, http_method)
        # print response.content
        response_json = response.json()
        # print json.dumps(response_json,indent=2)
        if 'error' in response_json:
            self._logger.error('Error in response from server on request to '+url+' : '+response_json['error'])
            raise Exception(response_json['error'])
        return response_json


    def _query(self, url, params={}, http_method='GET'):
        self._logger.debug("query "+http_method+" to "+url+" with "+str(params))
        if not isinstance(params, dict):
            raise Exception('Queries must include a dict of parameters')
        if 'key' not in params:
            params['key'] = self._auth_token
        if http_method is 'GET':
            r = requests.get(url, params=params, headers={ 'Accept': 'application/json'} )
        elif http_method is 'PUT':
            r = requests.put( url, params=params, headers={ 'Accept': 'application/json'} )
        else:
            raise Exception('Error - unsupported HTTP method '+str(http_method))
        if r.status_code is not 200:
            self._logger.error('Bad HTTP response to '+url+' : '+str(r.status_code))
            raise Exception('Error - got a HTTP status code of '+str(r.status_code))
        return r

# used when calling WriteableMediaCloud.tagStories
StoryTag = namedtuple('StoryTag',['stories_id','tag_set_name','tag_name'])

# used when calling WriteableMediaCloud.tagSentences
SentenceTag = namedtuple('SentenceTag',['story_sentences_id','tag_set_name','tag_name'])

class WriteableMediaCloud(MediaCloud):
    '''
    A MediaCloud API client that includes methods to write back data to MediaCloud.
    This is separated out from the base MediaCloud object to make it hard to accidentally 
    write data.
    '''

    def tagStories(self, tags={}, clear_others=False):
        '''
        Add some tags to stories. The tags parameter should be a list of StoryTag objects
        Returns ["1,rahulb@media.mit.edu:example_tag_2"] as response
curl -X PUT -d key=KEY -d story_tag=1,rahulb@media.mit.edu:example_tag_2 https://api.mediacloud.org/api/v2/stories/put_tags
        '''
        params = {}
        if clear_others is True:
            params['clear_tags'] = 1
        custom_tags = []
        for tag in tags:
            if tag.__class__ is not StoryTag:
                raise Exception('To use tagStories you must send in a list of StoryTag objects')
            custom_tags.append( '{},{}:{}'.format( tag.stories_id, tag.tag_set_name, tag.tag_name ) )
        params['story_tag'] = custom_tags
        return self._queryForJson( self.V2_API_URL+'stories/put_tags', params, 'PUT')

    def tagSentences(self, tags={}, clear_others=False):
        '''
        Add some tags to sentences. The tags parameter should be a list of SentenceTag objects
        '''
        params = {}
        if clear_others is True:
            params['clear_tags'] = 1
        custom_tags = []
        for tag in tags:
            if tag.__class__ is not SentenceTag:
                raise Exception('To use tagSentences you must send in a list of SentenceTag objects')
            custom_tags.append( '{},{}:{}'.format( tag.story_sentences_id, tag.tag_set_name, tag.tag_name ) )
        params['sentence_tag'] = custom_tags
        return self._queryForJson( self.V2_API_URL+'sentences/put_tags', params, 'PUT')
