import unittest, ConfigParser, json, datetime, logging
import mediacloud.api

class ApiBaseTest(unittest.TestCase):

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')
        self._mc = mediacloud.api.MediaCloud( self._config.get('api','key'), logging.DEBUG )
        requests_log = logging.getLogger("requests")
        requests_log.setLevel(logging.DEBUG)

class AuthTokenTest(ApiBaseTest):

    def testAuthToken(self):
        valid_auth_token = self._config.get('api','key')
        fake_auth_token = 'these are not the keys you are looking for'
        # make sure setAuthToken workds
        self._mc.setAuthToken(fake_auth_token)
        self.assertEqual(self._mc._auth_token,fake_auth_token)
        # see a request with a bad key fail
        try:
            self._mc.media(1)
            self.assertFalse(True)
        except:
            self.assertTrue(True)
        # set the key back to a valid one
        self._mc.setAuthToken(valid_auth_token)

    def testUserAuthToken(self):
        # test failure mode 
        try:
            self._mc.userAuthToken('user@funkytown.us','1234')
            self.assertFalse(True)
        except:
            self.assertTrue(True)

class ApiMediaTest(ApiBaseTest):

    def testMedia(self):
        media = self._mc.media(1)
        self.assertNotEqual(media, None)
        self.assertEqual(media['media_id'],1)
        self.assertEqual(media['name'],'New York Times')
        self.assertTrue(len(media['media_source_tags'])>0)
        self.assertTrue(len(media['media_sets'])>0)

    def testMediaListWithName(self):
        matchingList = self._mc.mediaList(name_like='new york times')
        self.assertEqual(len(matchingList),3)

    def testMediaList(self):
        firstList = self._mc.mediaList()
        for media in firstList:
            self.assertTrue(media['media_id']>0)
        self.assertNotEqual(firstList, None)
        self.assertEqual(len(firstList),20)
        last_page_one_media_id = int(firstList[19]['media_id'])-1
        self.assertTrue(last_page_one_media_id > 0)
        secondList = self._mc.mediaList(last_page_one_media_id)
        for media in secondList:
            self.assertTrue(media['media_id']>last_page_one_media_id)
        self.assertEqual(len(secondList),20)
        self.assertEqual(firstList[19]['media_id'], secondList[0]['media_id'])
        longerList = self._mc.mediaList(0,200)
        self.assertEqual(len(longerList),200)

class ApiTagsTest(ApiBaseTest):

    def testTags(self):
        tag = self._mc.tag(8876989)
        self.assertEqual(tag['tags_id'],8876989)
        self.assertEqual(tag['tag'],'japan')
        self.assertEqual(tag['tag_sets_id'],597)

    def testTagList(self):
        firstList = self._mc.tagList(597)
        self.assertEqual(len(firstList),20)
        [self.assertEqual(tag['tag_sets_id'],597) for tag in firstList]
        secondList = self._mc.tagList(597, int(firstList[19]['tags_id'])-1)
        self.assertEqual(len(secondList),20)
        [self.assertEqual(tag['tag_sets_id'],597) for tag in secondList]
        self.assertEqual(firstList[19]['tags_id'], secondList[0]['tags_id'])
        longerList = self._mc.tagList(597, 0, 150)
        self.assertEqual(len(longerList),150)
        [self.assertEqual(tag['tag_sets_id'],597) for tag in longerList]
        longestList = self._mc.tagList(597, 0, 200)
        self.assertEqual(len(longestList),173)
        [self.assertEqual(tag['tag_sets_id'],597) for tag in longestList]

class ApiTagSetsTest(ApiBaseTest):

    def testTagSet(self):
        tagSet = self._mc.tagSet(597)
        self.assertEqual(tagSet['tag_sets_id'],597)
        self.assertEqual(tagSet['name'],'gv_country')

    def testTagSetList(self):
        firstList = self._mc.tagSetList()
        self.assertEqual(len(firstList),20)
        secondList = self._mc.tagSetList(int(firstList[19]['tag_sets_id'])-1)
        self.assertEqual(len(secondList),20)
        self.assertEqual(firstList[19]['tag_sets_id'], secondList[0]['tag_sets_id'])
        longerList = self._mc.tagSetList(0,50)
        self.assertEqual(len(longerList),50)

class ApiMediaSetTest(ApiBaseTest):

    def testMediaSet(self):
        media_set = self._mc.mediaSet(1)
        self.assertEqual(media_set['media_sets_id'],1)
        self.assertEqual(media_set['name'],'Top 25 Mainstream Media')
        #self.assertTrue(len(media_set['media'])>0) # blocked by Media Cloud bug #7511 

    def testMediaSetList(self):
        firstList = self._mc.mediaSetList()
        self.assertEqual(len(firstList),20)
        secondList = self._mc.mediaSetList(int(firstList[19]['media_sets_id'])-1)
        self.assertEqual(len(secondList),20)
        self.assertEqual(firstList[19]['media_sets_id'], secondList[0]['media_sets_id'])
        longerList = self._mc.mediaSetList(0,200)
        self.assertEqual(len(longerList),200)

class ApiFeedsTest(ApiBaseTest):

    def testFeed(self):
        media_set = self._mc.feed(1)
        self.assertEqual(media_set['feeds_id'],1)
        self.assertEqual(media_set['name'],'Bits')
        self.assertEqual(media_set['media_id'],1)

    def testFeedList(self):
        firstList = self._mc.feedList(1)
        self.assertEqual(len(firstList),20)
        secondList = self._mc.feedList(1,int(firstList[19]['feeds_id'])-1)
        self.assertEqual(len(secondList),20)
        self.assertEqual(firstList[19]['feeds_id'], secondList[0]['feeds_id'])
        longerList = self._mc.feedList(1,0,200)
        self.assertEqual(len(longerList),140)

class ApiDashboardsTest(ApiBaseTest):

    def testDashboard(self):
        dashboard = self._mc.dashboard(2)
        self.assertEqual(dashboard['dashboards_id'],2)
        self.assertEqual(dashboard['name'],'Russia')
        self.assertTrue(len(dashboard['media_sets'])>0)

    def testDashboardList(self):
        firstList = self._mc.dashboardList()
        self.assertTrue(len(firstList)>0)

class ApiStoriesTest(ApiBaseTest):

    def testStory(self):
        story = self._mc.story(27456565)
        self.assertEqual(story['media_id'],1144)
        self.assertTrue(len(story['story_sentences'])>0)

    def testStoryList(self):
        results = self._mc.storyList('+obama', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
        self.assertNotEqual(len(results),0)

class ApiSentencesTest(ApiBaseTest):

    def testSentenceListSorting(self):
        date_format = self._mc.SENTENCE_PUBLISH_DATE_FORMAT
        q = '( mars OR robot )'
        fq = '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1'
        # ascending
        results = self._mc.sentenceList(q,fq,0,1000,self._mc.SORT_PUBLISH_DATE_ASC)
        self.assertEqual(len(results['response']['docs']), 1000)
        last_date = None
        for sentence in results['response']['docs']:
            this_date = datetime.datetime.strptime(sentence['publish_date'],date_format)
            if last_date is not None:
                self.assertTrue(last_date <= this_date, "Date wrong: "+str(last_date)+" is not < "+str(this_date))
                last_date = this_date
            last_date = this_date
        # descending
        results = self._mc.sentenceList(q,fq,0,1000,self._mc.SORT_PUBLISH_DATE_DESC)
        self.assertEqual(len(results['response']['docs']), 1000)
        last_date = None
        for sentence in results['response']['docs']:
            this_date = datetime.datetime.strptime(sentence['publish_date'],date_format)
            if last_date is not None:
                self.assertTrue(last_date >= this_date, "Date wrong: "+str(last_date)+" is not > "+str(this_date))
                last_date = this_date
            last_date = this_date

    def testSentenceList(self):
        results = self._mc.sentenceList('( mars OR robot )', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
        self.assertEqual(int(results['responseHeader']['status']),0)
        self.assertEqual(int(results['response']['numFound']),6735)
        self.assertEqual(len(results['response']['docs']), 1000)

    def testSentenceListPaging(self):
        query_str = '( mars OR robot )'
        filter_str = '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1'
        # test limiting rows returned
        results = self._mc.sentenceList(query_str, filter_str,0,100)
        self.assertEqual(int(results['response']['numFound']), 6781)
        self.assertEqual(len(results['response']['docs']), 100)
        # test starting offset
        results = self._mc.sentenceList(query_str, filter_str,6700)
        self.assertEqual(int(results['response']['numFound']), 6735)
        self.assertEqual(len(results['response']['docs']), 35)

    def testSentenceCount(self):
        # basic counting
        results = self._mc.sentenceCount('obama','+media_id:1')
        self.assertTrue(int(results['count'])>10000)
        # counting with a default split weekly
        results = self._mc.sentenceCount('obama','+media_id:1',True,'2014-01-01','2014-03-01')
        self.assertEqual(results['split']['gap'],'+7DAYS')
        self.assertEqual(len(results['split']),12)
        # counting with a default split 3-day
        results = self._mc.sentenceCount('obama','+media_id:1',True,'2014-01-01','2014-02-01')
        self.assertEqual(results['split']['gap'],'+3DAYS')
        self.assertEqual(len(results['split']),14)
        # counting with a default split daily
        results = self._mc.sentenceCount('obama','+media_id:1',True,'2014-01-01','2014-01-07')
        self.assertEqual(results['split']['gap'],'+1DAY')
        self.assertEqual(len(results['split']),9)
        # test forcing a daily split
        results = self._mc.sentenceCount('obama','+media_id:1',True,'2014-01-01','2014-02-01',True)
        self.assertEqual(results['split']['gap'],'+1DAY')
        self.assertEqual(len(results['split']),34)

class ApiWordCountTest(ApiBaseTest):

    def testWordCount(self):
        term_freq = self._mc.wordCount('+robots', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
        self.assertEqual(len(term_freq),69)
        self.assertEqual(term_freq[3]['term'],u'science')
        # verify sorted in desc order
        last_count = 10000000000
        for freq in term_freq:
            self.assertTrue( last_count >= freq['count'] )
            last_count = freq['count']

class WriteableApiTest(unittest.TestCase):

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')
        self._mc = mediacloud.api.WriteableMediaCloud( self._config.get('api','key'), logging.DEBUG )
        requests_log = logging.getLogger("requests")
        requests_log.setLevel(logging.DEBUG)

    def testTagStories(self):
        test_story_id = 1
        tag_set_name = "rahulb@media.mit.edu"
        # tag a story with two things
        desired_tags = [ mediacloud.api.StoryTag(test_story_id, tag_set_name, 'test_tag1'),
                 mediacloud.api.StoryTag(test_story_id, tag_set_name, 'test_tag2') ] 
        response = self._mc.tagStories(desired_tags)
        self.assertEqual(len(response),len(desired_tags))
        # make sure it worked
        story = self._mc.story(test_story_id)
        tags_on_story = [t for t in story['story_tags'] if t['tag_set']==tag_set_name]
        self.assertEqual(len(tags_on_story),len(desired_tags))
        # now remove one
        desired_tags = [ mediacloud.api.StoryTag(1,'rahulb@media.mit.edu','test_tag1') ]
        response = self._mc.tagStories(desired_tags, clear_others=True)
        self.assertEqual(len(response),len(desired_tags))
        # and check it
        story = self._mc.story(test_story_id)
        tags_on_story = [t for t in story['story_tags'] if t['tag_set']==tag_set_name]
        self.assertEqual(len(tags_on_story),len(desired_tags))
