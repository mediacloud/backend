
import re, logging, json, urllib
import xml.etree.ElementTree, requests
import mediacloud

class MediaCloud(object):
    '''
    Simple client library for the nascent MediaCloud story feed API
    '''

    V2_API_URL = "http://www.mediacloud.org/api/v2/"
    API_URL = "http://mediacloud.org/admin/api/"
    SOLR_URL = "http://mediacloud.org/admin/query/"
    DEFAULT_STORY_COUNT = 25
    DEFAULT_SOLR_SENTENCES_PER_PAGE = 5000

    def __init__(self, api_user=None, api_pass=None):
        logging.basicConfig(filename='mediacloud-api.log',level=logging.DEBUG)
        self._api_user = api_user
        self._api_pass = api_pass

    def allProcessed(self, page=1):
        '''
        Return the lastest fully processed 20 stories (ie. with sentences pulled out)
        '''
        return self._queryForJson(self.API_URL+'stories/all_processed', { 'page':page } )

    def storyDetails(self, story_id):
        '''
        Return full informatino about one story
        '''
        return self._queryForJson(self.V2_API_URL+'stories/stories_query/'+str(story_id))[0]

    def _queryForJson(self, url, params={}, http_method='GET'):
        '''
        Helper that actually makes the requests and returns json
        '''
        r = self._query(url, params, http_method)
        return r.json()

    def _query(self, url, params={}, http_method='GET'):
        '''
        Helper that actually makes the requests and returns json
        '''
        logging.debug("query "+url+" with "+str(params))
        r = requests.request( http_method, url, 
            params=params,
            auth=(self._api_user, self._api_pass), 
            headers={ 'Accept': 'application/json'}  
        )
        return r

    def wordCount(self, query_str, filter_str):
        '''
        Return an array of word counts from sentences matching the query and filter specified.
        This returns a JSON array of things like this: {u'count': 1, u'term': u'versatile', u'stem': u'versatil'}.
        query_str should be something like this: "( robots OR android ) AND ( space )".
        filter_str should be something like this: "+publish_date:[2012-04-01T00:00:00Z TO 2012-04-02T00:00:00Z] AND +media_sets_id:1".
        '''
        results = self._queryForJson(self.SOLR_URL+'wc', { 'q': query_str, 'fq': filter_str} )
        return results

    def sentencesMatching(self, query_str, filter_str, start=0, rows=DEFAULT_SOLR_SENTENCES_PER_PAGE):
        '''
        Return an array of sentences matching the query and filter specified.
        query_str should be something like this: "( robots AND mars ) OR ( space AND mars )".
        filter_str should be something like this: "+publish_date:[2012-04-01T00:00:00Z TO 2012-04-02T00:00:00Z] AND +media_sets_id:1".
        '''
        return self._queryForJson(self.SOLR_URL+'sentences', { 'q': query_str, 'fq': filter_str, 
            'start': start, 'rows': rows } )

    def sentencesMatchingByStory(self, query_str, filter_str, start=0, rows=DEFAULT_SOLR_SENTENCES_PER_PAGE):
        '''
        Same as sentencesMatching, but groups sentences by story_id for you 
        (returns as a dict mapping story_id to array of sentence results)
        '''
        results = self.sentencesMatching(query_str, filter_str, start, rows)
        stories = {}
        for sentence in results['response']['docs']:
            story_id = sentence['stories_id']
            if story_id not in stories:
                stories[story_id] = []
            stories[story_id].append(sentence)
        return stories
