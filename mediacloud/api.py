
import re, logging, json, urllib
import xml.etree.ElementTree, requests
import mediacloud

class MediaCloud(object):
    '''
    Simple client library for the nascent MediaCloud story feed API
    '''

    API_URL = "http://mediacloud.org/admin/"
    DEFAULT_STORY_COUNT = 25
    DEFAULT_SOLR_SENTENCES_PER_PAGE = 100

    def __init__(self, api_user=None, api_pass=None):
        logging.basicConfig(filename='mediacloud-api.log',level=logging.DEBUG)
        self._api_user = api_user
        self._api_pass = api_pass

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
        results = self._queryForJson('api/stories/subset/', {'data':json.dumps(params,separators=(',',':'))}, 'PUT' )
        return results['story_subsets_id']

    def _storySubsetDetail(self, subset_id):
        return self._queryForJson('api/stories/subset/'+str(subset_id), {})

    def isStorySubsetReady(self, subset_id):
        '''
        Checks if a story subset is complete.  This can take a while.  Returns true or false.
        Once it returns true, you can page through the stories with allProcessedInSubset
        '''
        subset_info = self._storySubsetDetail(subset_id)
        return (subset_info['ready']==1)

    def allProcessedInSubset(self,subset_id, page=1):
        '''
        Retrieve all the processed stories within a certain subset, 20 at a time
        '''
        return self._queryForJson('api/stories/subset_processed/'+str(subset_id), { 'page':page } )

    def allProcessed(self, page=1):
        '''
        Return the lastest fully processed 20 stories (ie. with sentences pulled out)
        '''
        return self._queryForJson('api/stories/all_processed', { 'page':page } )

    def _queryForJson(self, method, params={}, http_method='GET'):
        '''
        Helper that actually makes the requests and returns json
        '''
        r = self._query(method, params, http_method)
        return r.json()

    def _query(self, method, params={}, http_method='GET'):
        '''
        Helper that actually makes the requests and returns json
        '''
        url = self.API_URL + method
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
        return self._queryForJson('query/wc', { 'q': query_str, 'fq': filter_str} )

    def sentencesMatching(self, query_str, filter_str, start=0, rows=DEFAULT_SOLR_SENTENCES_PER_PAGE):
        '''
        Return an array of sentences matching the query and filter specified.
        query_str should be something like this: "( robots AND mars ) OR ( space AND mars )".
        filter_str should be something like this: "+publish_date:[2012-04-01T00:00:00Z TO 2012-04-02T00:00:00Z] AND +media_sets_id:1".
        '''
        return self._queryForJson('query/sentences', { 'q': query_str, 'fq': filter_str, 
            'start': start, 'rows': rows } )

