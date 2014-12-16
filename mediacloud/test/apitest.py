import unittest, ConfigParser, json, datetime, logging
import mediacloud.api

class ApiBaseTest(unittest.TestCase):

    QUERY = '( mars OR robot )'
    FILTER_QUERY = '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1'

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')
        self._mc = mediacloud.api.MediaCloud( self._config.get('api','key'))

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
        first_list = self._mc.mediaList()
        for media in first_list:
            self.assertTrue(media['media_id']>0)
        self.assertNotEqual(first_list, None)
        self.assertEqual(len(first_list),20)
        last_page_one_media_id = int(first_list[19]['media_id'])-1
        self.assertTrue(last_page_one_media_id > 0)
        second_list = self._mc.mediaList(last_page_one_media_id)
        for media in second_list:
            self.assertTrue(media['media_id']>last_page_one_media_id)
        self.assertEqual(len(second_list),20)
        self.assertEqual(first_list[19]['media_id'], second_list[0]['media_id'])
        longer_list = self._mc.mediaList(0,200)
        self.assertEqual(len(longer_list),200)

class ApiControversyTest(ApiBaseTest):

    def testControversy(self):
        controversy = self._mc.controversy(1)
        self.assertEqual(controversy['controversies_id'],1)
        self.assertEqual(controversy['name'],'trayvon')

    def testControversyList(self):
        # verify it pulls some
        controversy_list = self._mc.controversyList()
        self.assertTrue(len(controversy_list)>1)
        # make sure the filtering works
        pop_controversy_list = self._mc.controversyList('prop')
        self.assertTrue(len(pop_controversy_list)>1)
        self.assertTrue(len(pop_controversy_list)<len(controversy_list))
        # make sure a failure case works
        random_controversy_list = self._mc.controversyList('12335')
        self.assertEqual(len(random_controversy_list),0)

class ApiControversyDumpTest(ApiBaseTest):

    def testControversyDump(self):
        controversy_dump = self._mc.controversyDump(557)
        self.assertEqual(controversy_dump['controversy_dumps_id'],557)
        self.assertEqual(controversy_dump['controversies_id'],1)

    def testControversyDumpList(self):
        # verify it pulls some
        controversy_dump_list = self._mc.controversyDumpList()
        self.assertTrue(len(controversy_dump_list)>1)
        # make sure the filtering works
        specific_controversy_dump_list = self._mc.controversyDumpList(1)
        self.assertTrue(len(specific_controversy_dump_list)>1)
        self.assertTrue(len(specific_controversy_dump_list)<len(controversy_dump_list))
        # make sure a failure case works
        random_controversy_dump_list = self._mc.controversyDumpList('12335')
        self.assertEqual(len(random_controversy_dump_list),0)

class ApiControversyDumpTimeSliceTest(ApiBaseTest):

    def testControversyDumpTimeSlice(self):
        dump_time_slice = self._mc.controversyDumpTimeSlice(145)
        self.assertEqual(dump_time_slice['controversy_dump_time_slices_id'],145)
        self.assertEqual(dump_time_slice['controversy_dumps_id'],16)
        self.assertEqual(dump_time_slice['model_num_media'],4)

    def testControversyDumpTimeSliceList(self):
        # verify it pulls some
        dump_time_slice_list = self._mc.controversyDumpTimeSliceList()
        self.assertTrue(len(dump_time_slice_list)>1)
        # make sure the filtering works
        specific_dump_time_slice_list = self._mc.controversyDumpTimeSliceList(controversy_dumps_id=5)
        self.assertTrue(len(specific_dump_time_slice_list)>1)
        self.assertTrue(len(specific_dump_time_slice_list)<=len(dump_time_slice_list))

class ApiTagsTest(ApiBaseTest):

    def testTags(self):
        tag = self._mc.tag(8876989)
        self.assertEqual(tag['tags_id'],8876989)
        self.assertEqual(tag['tag'],'JP')
        self.assertEqual(tag['tag_sets_id'],597)

    def testTagList(self):
        # verify it only pulls tags from that one set
        first_list = self._mc.tagList(597)
        self.assertEqual(len(first_list),20)
        [self.assertEqual(tag['tag_sets_id'],597) for tag in first_list]
        # make sure paging through a set works right
        second_list = self._mc.tagList(597, int(first_list[19]['tags_id'])-1)
        self.assertEqual(len(second_list),20)
        [self.assertEqual(tag['tag_sets_id'],597) for tag in second_list]
        self.assertEqual(first_list[19]['tags_id'], second_list[0]['tags_id'])
        # make sure you can pull a longer list of tags
        longer_list = self._mc.tagList(597, 0, 150)
        self.assertEqual(len(longer_list),150)
        [self.assertEqual(tag['tag_sets_id'],597) for tag in longer_list]
        longest_list = self._mc.tagList(597, 0, 200)
        self.assertEqual(len(longest_list),173)
        [self.assertEqual(tag['tag_sets_id'],597) for tag in longest_list]
        # try getting only the public tags in the set
        full_list = self._mc.tagList(6, rows=200)
        public_list = self._mc.tagList(6, rows=200, public_only=True)
        self.assertNotEqual( len(full_list), len(public_list))

class ApiTagSetsTest(ApiBaseTest):

    def testTagSet(self):
        tagSet = self._mc.tagSet(597)
        self.assertEqual(tagSet['tag_sets_id'],597)
        self.assertEqual(tagSet['name'],'gv_country')

    def testTagSetList(self):
        first_list = self._mc.tagSetList()
        self.assertEqual(len(first_list),20)
        second_list = self._mc.tagSetList(int(first_list[19]['tag_sets_id'])-1)
        self.assertEqual(len(second_list),20)
        self.assertEqual(first_list[19]['tag_sets_id'], second_list[0]['tag_sets_id'])
        longer_list = self._mc.tagSetList(0,50)
        self.assertEqual(len(longer_list),50)

class ApiMediaSetTest(ApiBaseTest):

    def testMediaSet(self):
        media_set = self._mc.mediaSet(1)
        self.assertEqual(media_set['media_sets_id'],1)
        self.assertEqual(media_set['name'],'Top 25 Mainstream Media')
        self.assertTrue(len(media_set['media'])>0)

    def testMediaSetList(self):
        first_list = self._mc.mediaSetList()
        self.assertEqual(len(first_list),20)
        second_list = self._mc.mediaSetList(int(first_list[19]['media_sets_id'])-1)
        self.assertEqual(len(second_list),20)
        self.assertEqual(first_list[19]['media_sets_id'], second_list[0]['media_sets_id'])
        longer_list = self._mc.mediaSetList(0,200)
        self.assertEqual(len(longer_list),200)

class ApiFeedsTest(ApiBaseTest):

    def testFeed(self):
        media_set = self._mc.feed(1)
        self.assertEqual(media_set['feeds_id'],1)
        self.assertEqual(media_set['name'],'Bits')
        self.assertEqual(media_set['media_id'],1)

    def testFeedList(self):
        first_list = self._mc.feedList(1)
        self.assertEqual(len(first_list),20)
        second_list = self._mc.feedList(1,int(first_list[19]['feeds_id'])-1)
        self.assertEqual(len(second_list),20)
        self.assertEqual(first_list[19]['feeds_id'], second_list[0]['feeds_id'])
        longer_list = self._mc.feedList(1,0,200)
        self.assertEqual(len(longer_list),140)

class ApiDashboardsTest(ApiBaseTest):

    def testDashboard(self):
        dashboard = self._mc.dashboard(2)
        self.assertEqual(dashboard['dashboards_id'],2)
        self.assertEqual(dashboard['name'],'Russia')
        self.assertTrue(len(dashboard['media_sets'])>0)

    def testDashboardList(self):
        first_list = self._mc.dashboardList()
        self.assertTrue(len(first_list)>0)

class ApiStoriesTest(ApiBaseTest):

    def testStory(self):
        story = self._mc.story(27456565)
        self.assertEqual(story['media_id'],1144)
        self.assertFalse('story_sentences' in story)

    def testStoryList(self):
        results = self._mc.storyList(self.QUERY, self.FILTER_QUERY)
        self.assertNotEqual(len(results),0)

    def testStoryPublic(self):
        story = self._mc.storyPublic(27456565)
        self.assertEqual(story['media_id'],1144)
        self.assertTrue('story_sentences' not in story)

    def testStoryPublicList(self):
        results = self._mc.storyList(self.QUERY, self.FILTER_QUERY)
        self.assertNotEqual(len(results),0)

    def testStoryCoreNlpList(self):
        results = self._mc.storyCoreNlpList([261784668,261784669])
        self.assertEqual(len(results),2)
        for story in results:
            self.assertFalse('story_sentences' in story)
            self.assertFalse('story_text' in story)
            self.assertFalse('fully_extracted' in story)
            self.assertTrue('corenlp' in story)
            self.assertTrue('stories_id' in story)

'''
    def testStoryListDefaults(self):
        results = self._mc.storyList(self.QUERY, self.FILTER_QUERY)
        for story in results:
            self.assertTrue('story_sentences' in story)
            self.assertTrue('story_text' in story)
            self.assertTrue('fully_extracted' in story)
            self.assertFalse('corenlp' in story)

    def testStoryListWithCoreNlp(self):
        results = self._mc.storyList(self.QUERY, self.FILTER_QUERY, corenlp=True)
        for story in results:
            self.assertFalse('story_sentences' in story)
            self.assertTrue('story_text' in story)
            self.assertTrue('fully_extracted' in story)
            self.assertFalse('corenlp' in story)

    def testStoryListWithoutSentences(self):
        results = self._mc.storyList(self.QUERY, self.FILTER_QUERY, show_sentences=False)
        for story in results:
            self.assertFalse('story_sentences' in story)
            self.assertTrue('story_text' in story)
            self.assertTrue('fully_extracted' in story)
            self.assertFalse('corenlp' in story)

    def testStoryListWithoutText(self):
        results = self._mc.storyList(self.QUERY, self.FILTER_QUERY, show_text=False)
        for story in results:
            self.assertTrue('story_sentences' in story)
            self.assertFalse('story_text' in story)
            self.assertFalse('fully_extracted' in story)
            self.assertFalse('corenlp' in story)
'''

class ApiSentencesTest(ApiBaseTest):

    SENTENCE_COUNT = 100

    def testSentenceListSortingAscending(self):
        results = self._mc.sentenceList(self.QUERY,self.FILTER_QUERY,0,self.SENTENCE_COUNT,
            self._mc.SORT_PUBLISH_DATE_ASC)
        self.assertEqual(len(results['response']['docs']), self.SENTENCE_COUNT)
        last_date = None
        for sentence in results['response']['docs']:
            this_date = datetime.datetime.strptime(sentence['publish_date'],self._mc.SENTENCE_PUBLISH_DATE_FORMAT)
            this_date = this_date.replace( second=0, microsecond=0) # sorting is by minute
            if last_date is not None:
                self.assertTrue(last_date <= this_date, "Date wrong: "+str(last_date)+" is not <= "+str(this_date))
                last_date = this_date
            last_date = this_date
        
    def testSentenceListSortingDescending(self):
        results = self._mc.sentenceList(self.QUERY,self.FILTER_QUERY,0,self.SENTENCE_COUNT,
            self._mc.SORT_PUBLISH_DATE_DESC)
        self.assertEqual(len(results['response']['docs']), self.SENTENCE_COUNT)
        last_date = None
        for sentence in results['response']['docs']:
            this_date = datetime.datetime.strptime(sentence['publish_date'],self._mc.SENTENCE_PUBLISH_DATE_FORMAT)
            this_date = this_date.replace( second=0, microsecond=0) # sorting is by minute
            if last_date is not None:
                self.assertTrue(last_date >= this_date, "Date wrong: "+str(last_date)+" is not >= "+str(this_date))
                last_date = this_date
            last_date = this_date

    def testSentenceListSortingRadom(self):
        # we do random sort by telling we want the random sort, and then offsetting to a different start index
        results1 = self._mc.sentenceList(self.QUERY,self.FILTER_QUERY,0,self.SENTENCE_COUNT,
            self._mc.SORT_RANDOM)
        self.assertEqual(len(results1['response']['docs']), self.SENTENCE_COUNT)
        results2 = self._mc.sentenceList(self.QUERY,self.FILTER_QUERY,self.SENTENCE_COUNT,self.SENTENCE_COUNT,
            self._mc.SORT_RANDOM)
        self.assertEqual(len(results2['response']['docs']), self.SENTENCE_COUNT)
        for idx in range(0,self.SENTENCE_COUNT):
            self.assertNotEqual(results1['response']['docs'][idx]['stories_id'],results2['response']['docs'][idx]['stories_id'],
                "Stories in two different random sets are the same :-(")

    def testSentenceList(self):
        results = self._mc.sentenceList(self.QUERY, self.FILTER_QUERY)
        self.assertEqual(int(results['responseHeader']['status']),0)
        self.assertEqual(int(results['response']['numFound']),6739)
        self.assertEqual(len(results['response']['docs']), 1000)

    def testSentenceListPaging(self):
        # test limiting rows returned
        results = self._mc.sentenceList(self.QUERY, self.FILTER_QUERY,0,100)
        self.assertEqual(int(results['response']['numFound']), 6739)
        self.assertEqual(len(results['response']['docs']), 100)
        # test starting offset
        results = self._mc.sentenceList(self.QUERY, self.FILTER_QUERY,6700)
        self.assertEqual(int(results['response']['numFound']), 6739)
        self.assertEqual(len(results['response']['docs']), 39)

    def testSentenceCount(self):
        # basic counting
        results = self._mc.sentenceCount('obama','+media_id:1')
        self.assertTrue(int(results['count'])>10000)
        # counting with a default split weekly (>180 days)
        results = self._mc.sentenceCount('obama','+media_id:1',True,'2013-01-01','2014-01-01')
        self.assertEqual(results['split']['gap'],'+7DAYS')
        self.assertEqual(len(results['split']),56)
        # counting with a default split 3-day (<180 days, >90 days)
        results = self._mc.sentenceCount('obama','+media_id:1',True,'2014-01-01','2014-06-01')
        self.assertEqual(results['split']['gap'],'+3DAYS')
        self.assertEqual(len(results['split']),54)
        # counting with a default split daily (<90 days)
        results = self._mc.sentenceCount('obama','+media_id:1',True,'2014-01-01','2014-01-07')
        self.assertEqual(results['split']['gap'],'+1DAY')
        self.assertEqual(len(results['split']),9)
        # test forcing a daily split
        results = self._mc.sentenceCount('obama','+media_id:1',True,'2014-01-01','2014-06-01',True)
        self.assertEqual(results['split']['gap'],'+1DAY')
        self.assertEqual(len(results['split']),154)

class ApiWordCountTest(ApiBaseTest):

    QUERY = 'robots'

    def testResults(self):
        term_freq = self._mc.wordCount(self.QUERY, self.FILTER_QUERY)
        self.assertEqual(len(term_freq),500)
        self.assertEqual(term_freq[3]['term'],u'science')

    def testSort(self):
        term_freq = self._mc.wordCount(self.QUERY, self.FILTER_QUERY)
        # verify sorted in desc order
        last_count = 10000000000
        for freq in term_freq:
            self.assertTrue( last_count >= freq['count'] )
            last_count = freq['count']

    def testNumWords(self):
        term_freq = self._mc.wordCount(self.QUERY, self.FILTER_QUERY)
        self.assertEqual(len(term_freq),500)
        term_freq = self._mc.wordCount(self.QUERY, self.FILTER_QUERY, num_words=100)
        self.assertEqual(len(term_freq),100)

    def testStopWords(self):
        term_freq = self._mc.wordCount(self.QUERY, self.FILTER_QUERY)
        self.assertEqual(term_freq[3]['term'],u'science')
        term_freq = self._mc.wordCount(self.QUERY, self.FILTER_QUERY, include_stopwords=True)
        self.assertEqual(term_freq[3]['term'],u'that')        

    def testStats(self):
        term_freq = self._mc.wordCount(self.QUERY, self.FILTER_QUERY)
        self.assertEqual(term_freq[3]['term'],u'science')
        term_freq = self._mc.wordCount(self.QUERY, self.FILTER_QUERY, include_stats=True)
        self.assertEqual(len(term_freq),2)
        self.assertTrue( 'stats' in term_freq.keys() )
        self.assertTrue( 'words' in term_freq.keys() )

class WriteableApiTest(unittest.TestCase):

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')
        self._mc = mediacloud.api.WriteableMediaCloud( self._config.get('api','key') )

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

    def testTagSentences(self):
        test_story_id = 150891343
        test_tag_id1 = '8878341' # rahulb@media.mit.edu:test_tag1
        test_tag_id2 = '8878342' # rahulb@media.mit.edu:test_tag2
        tag_set_name = "rahulb@media.mit.edu"
        # grab some sentence_ids to test with
        orig_story = self._mc.story(test_story_id)
        self.assertTrue( len(orig_story['story_sentences']) > 2 )
        sentence_ids = [ s['story_sentences_id'] for s in orig_story['story_sentences'][0:2] ]
        # add a tag
        desired_tags = [ mediacloud.api.SentenceTag(sid, tag_set_name, 'test_tag1') 
            for sid in sentence_ids ]
        response = self._mc.tagSentences(desired_tags)
        self.assertEqual(len(response),len(desired_tags))
        # and verify it worked
        tagged_story = self._mc.story(test_story_id)
        tagged_sentences = [ s for s in orig_story['story_sentences'] if len(s['tags']) > 0 ]
        for s in tagged_sentences:
            if s['story_sentences_id'] in sentence_ids:
                self.assertTrue(test_tag_id1 in s['tags'])
        # now do two tags on each story
        desired_tags = desired_tags + [ mediacloud.api.SentenceTag(sid, tag_set_name, 'test_tag2') 
            for sid in sentence_ids ]
        response = self._mc.tagSentences(desired_tags)
        self.assertEqual(len(response),len(desired_tags))
        # and verify it worked
        tagged_story = self._mc.story(test_story_id)
        tagged_sentences = [ s for s in tagged_story['story_sentences'] if len(s['tags']) > 0 ]
        for s in tagged_sentences:
            if s['story_sentences_id'] in sentence_ids:
                self.assertTrue(test_tag_id1 in s['tags'])
                self.assertTrue(test_tag_id2 in s['tags'])
        # now remove one
        desired_tags = [ mediacloud.api.SentenceTag(sid, tag_set_name, 'test_tag1') 
            for sid in sentence_ids ]
        response = self._mc.tagSentences(desired_tags, clear_others=True)
        self.assertEqual(len(response),len(desired_tags))
        # and check it
        tagged_story = self._mc.story(test_story_id)
        tagged_sentences = [ s for s in tagged_story['story_sentences'] if len(s['tags']) > 0 ]
        for s in tagged_sentences:
            if s['story_sentences_id'] in sentence_ids:
                self.assertTrue(test_tag_id1 in s['tags'])
                self.assertFalse(test_tag_id2 in s['tags'])
