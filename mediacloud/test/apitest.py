import unittest, ConfigParser, json
import mediacloud.api

class ApiBaseTest(unittest.TestCase):

    def setUp(self):
       self._config = ConfigParser.ConfigParser()
       self._config.read('mc-client.config')
       self._mc = mediacloud.api.MediaCloud( self._config.get('api','key') )

class ApiMediaTest(ApiBaseTest):

    def testMedia(self):
        media = self._mc.media(1)
        self.assertNotEqual(media, None)
        self.assertEqual(media['media_id'],1)
        self.assertEqual(media['name'],'New York Times')
        self.assertTrue(len(media['media_source_tags'])>0)
        self.assertTrue(len(media['media_sets'])>0)

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
        results = self._mc.storyList('robot','+publish_date:[2013-01-01T00:00:00Z TO 2013-12-31T00:00:00Z] AND +media_sets_id:1')
        self.assertNotEqual(len(results),0)

class ApiSentencesTest(ApiBaseTest):

    def testSentenceList(self):
        results = self._mc.sentenceList('( mars OR robot )', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
        self.assertEqual(int(results['responseHeader']['status']),0)
        self.assertEqual(int(results['response']['numFound']),6742)
        self.assertEqual(len(results['response']['docs']), 1000)

    def testSentenceListPaging(self):
        query_str = '( mars OR robot )'
        filter_str = '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1'
        # test limiting rows returned
        results = self._mc.sentenceList(query_str, filter_str,0,100)
        self.assertEqual(int(results['response']['numFound']), 6742)
        self.assertEqual(len(results['response']['docs']), 100)
        # test starting offset
        results = self._mc.sentenceList(query_str, filter_str,6700)
        self.assertEqual(int(results['response']['numFound']), 6742)
        self.assertEqual(len(results['response']['docs']), 42)

class ApiWordCountTest(ApiBaseTest):

    def testWordCount(self):
        term_freq = self._mc.wordCount('robots', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
        self.assertEqual(len(term_freq),71)
        self.assertEqual(term_freq[3]['term'],u'drones')
        # verify sorted in desc order
        last_count = 10000000000
        for freq in term_freq:
            self.assertTrue( last_count >= freq['count'] )
            last_count = freq['count']
