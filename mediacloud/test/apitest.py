import unittest, ConfigParser, json, datetime, logging
import mediacloud.api

TEST_USER_EMAIL = "mc-api-test@media.mit.edu"
TEST_TAG_SET_ID = 1727

class ApiBaseTest(unittest.TestCase):

    QUERY = '( mars OR robot )'
    FILTER_QUERY = '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1'
    SENTENCE_COUNT = 100

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')
        self._mc = mediacloud.api.MediaCloud( self._config.get('api','key'))

class AdminApiBaseTest(unittest.TestCase):

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')
        self._mc = mediacloud.api.AdminMediaCloud( self._config.get('api','key') )

class ApiAllFieldsOptionTest(ApiBaseTest):

    def testAllFieldsOnMedia(self):
        # do a regular query
        media = self._mc.media(1751)
        self.assertNotEqual(media, None)
        self.assertEqual(media['media_id'],1751)
        self.assertFalse('foreign_rss_links' in media)
        self.assertTrue('url' in media)
        # do an all fields regular query and verify extra fields are there
        self._mc.setAllFields(True)
        media = self._mc.media(1751)
        self.assertNotEqual(media, None)
        self.assertEqual(media['media_id'],1751)
        self.assertTrue('foreign_rss_links' in media)
        self.assertTrue('url' in media)

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

class PublishDateQueryTest(ApiBaseTest):

    def testPublishDateQuery(self):
        start_date = datetime.date(2014,06,02 )
        end_date = datetime.date(2014,06,03 )
        date_query_default = self._mc.publish_date_query( start_date, end_date )
        self.assertEqual( date_query_default, "publish_date:[2014-06-02T00:00:00Z TO 2014-06-03T00:00:00Z}" )

        date_query_inclusive_exclusive = self._mc.publish_date_query( start_date, end_date, start_date_inclusive=True, end_date_inclusive=False)
        self.assertEqual( date_query_inclusive_exclusive, "publish_date:[2014-06-02T00:00:00Z TO 2014-06-03T00:00:00Z}") 

        date_query_inclusive_inclusive = self._mc.publish_date_query( start_date, end_date, start_date_inclusive=True, end_date_inclusive=True)
        self.assertEqual( date_query_inclusive_inclusive, "publish_date:[2014-06-02T00:00:00Z TO 2014-06-03T00:00:00Z]") 

        date_query_exclusive_inclusive = self._mc.publish_date_query( start_date, end_date, start_date_inclusive=False, end_date_inclusive=True)
        self.assertEqual( date_query_exclusive_inclusive, "publish_date:{2014-06-02T00:00:00Z TO 2014-06-03T00:00:00Z]") 

        date_query_exclusive_exclusive = self._mc.publish_date_query( start_date, end_date, start_date_inclusive=False, end_date_inclusive=False)
        self.assertEqual( date_query_exclusive_exclusive, "publish_date:{2014-06-02T00:00:00Z TO 2014-06-03T00:00:00Z}") 

        self.assertTrue( self._mc.sentenceCount( date_query_default )[ 'count' ] > 0 )
        self.assertTrue( self._mc.sentenceCount( date_query_inclusive_exclusive )[ 'count' ] > 0 )
        self.assertTrue( self._mc.sentenceCount( date_query_inclusive_inclusive )[ 'count' ] > 0 )
        self.assertTrue( self._mc.sentenceCount( date_query_exclusive_exclusive )[ 'count' ] > 0 )
        self.assertTrue( self._mc.sentenceCount( date_query_exclusive_inclusive )[ 'count' ] > 0 )

class ApiMediaHealthTest(ApiBaseTest):

    def testMediaHealth(self):
        mediaHealth = self._mc.mediaHealth(2)
        self.assertEqual(mediaHealth['media_id'],'2')
        self.assertEqual(mediaHealth['is_healthy'],1)
        self.assertEqual(mediaHealth['coverage_gaps'],str(len(mediaHealth['coverage_gaps_list'])))
        self.assertTrue('start_date' in mediaHealth)
        self.assertTrue('end_date' in mediaHealth)

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

    def testMediaListWithTagId(self):
        matchingList = self._mc.mediaList(tags_id=8875027)  # US MSM
        self.assertTrue(len(matchingList)>0)

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
        specific_dump_time_slice_list = self._mc.controversyDumpTimeSliceList(controversy_dumps_id=16)
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

    def testTagListSearch(self):
        # verify search works at all
        collection_tags = self._mc.tagList(name_like="collection")
        self.assertTrue(len(collection_tags)>0, "Got %d tags matching 'collection'" % len(collection_tags))
        # verify search works on tags without descriptions
        geo_tags = self._mc.tagList(name_like="geonames_")
        self.assertTrue(len(geo_tags)>0, "Got %d tags matching 'geonames_'" % len(geo_tags))

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
        self.assertEqual(len(longer_list),141)

class AdminApiStoriesTest(AdminApiBaseTest):

    def testStoryWithSentences(self):
        story = self._mc.story(27456565, sentences=True)
        self.assertEqual(int(story['stories_id']),27456565)
        self.assertEqual(story['media_id'],1144)
        self.assertTrue('story_sentences' in story)
        self.assertFalse('story_text' in story)
        self.assertFalse('is_fully_extracted' in story)

    def testStoryWithText(self):
        story = self._mc.story(27456565, text=True)
        self.assertEqual(int(story['stories_id']),27456565)
        self.assertEqual(story['media_id'],1144)
        self.assertFalse('story_sentences' in story)
        self.assertTrue('story_text' in story)
        self.assertTrue('is_fully_extracted' in story)

    def testStoryList(self):
        results = self._mc.storyList(ApiBaseTest.QUERY, ApiBaseTest.FILTER_QUERY)
        self.assertNotEqual(len(results),0)
        for story in results:
            self.assertTrue('bitly_click_count' in story)

    def testStoryCoreNlpList(self):
        results = self._mc.storyCoreNlpList([261784668,261784669])
        self.assertEqual(len(results),2)
        for story in results:
            self.assertFalse('story_sentences' in story)
            self.assertFalse('story_text' in story)
            self.assertFalse('is_fully_extracted' in story)
            self.assertTrue('corenlp' in story)
            self.assertTrue('stories_id' in story)

    def testStoryListDefaults(self):
        results = self._mc.storyList(ApiBaseTest.QUERY, ApiBaseTest.FILTER_QUERY, rows=10)
        for story in results:
            self.assertFalse('story_sentences' in story)
            self.assertFalse('story_text' in story)
            self.assertFalse('is_fully_extracted' in story)
            self.assertFalse('corenlp' in story)

    def testStoryListWithCoreNlp(self):
        results = self._mc.storyList(ApiBaseTest.QUERY, ApiBaseTest.FILTER_QUERY, corenlp=True, rows=10)
        for story in results:
            self.assertFalse('story_sentences' in story)
            self.assertFalse('story_text' in story)
            self.assertFalse('is_fully_extracted' in story)
            self.assertTrue('corenlp' in story)

    def testStoryListWithSentences(self):
        results = self._mc.storyList(ApiBaseTest.QUERY, ApiBaseTest.FILTER_QUERY, sentences=True, rows=10)
        for story in results:
            self.assertTrue('story_sentences' in story)
            self.assertFalse('story_text' in story)
            self.assertFalse('is_fully_extracted' in story)
            self.assertFalse('corenlp' in story)

    def testStoryListWithText(self):
        results = self._mc.storyList(ApiBaseTest.QUERY, ApiBaseTest.FILTER_QUERY, text=True, rows=10)
        for story in results:
            self.assertFalse('story_sentences' in story)
            self.assertTrue('story_text' in story)
            self.assertTrue('is_fully_extracted' in story)
            self.assertFalse('corenlp' in story)

class ApiStoriesTest(ApiBaseTest):

    def testStory(self):
        story = self._mc.story(27456565)
        self.assertEqual(int(story['stories_id']),27456565)
        self.assertEqual(story['media_id'],1144)
        self.assertFalse('story_sentences' in story)
        self.assertFalse('story_text' in story)
        self.assertFalse('is_fully_extracted' in story)
        self.assertTrue('bitly_click_count' in story)

    def testStoryPublic(self):
        story = self._mc.story(27456565)
        self.assertEqual(story['media_id'],1144)
        self.assertTrue('story_sentences' not in story)
        self.assertTrue('language' in story)
        self.assertTrue('title' in story)
        self.assertTrue('bitly_click_count' in story)

    def testStoryPublicList(self):
        results = self._mc.storyList(self.QUERY, self.FILTER_QUERY)
        self.assertNotEqual(len(results),0)
        for story in results:
            self.assertTrue('bitly_click_count' in story)

class AdminApiSentencesTest(AdminApiBaseTest):

    def testSentenceListSortingAscending(self):
        results = self._mc.sentenceList(ApiBaseTest.QUERY,ApiBaseTest.FILTER_QUERY,0,ApiBaseTest.SENTENCE_COUNT,
            self._mc.SORT_PUBLISH_DATE_ASC)
        self.assertEqual(len(results['response']['docs']), ApiBaseTest.SENTENCE_COUNT)
        last_date = None
        for sentence in results['response']['docs']:
            this_date = datetime.datetime.strptime(sentence['publish_date'],self._mc.SENTENCE_PUBLISH_DATE_FORMAT)
            this_date = this_date.replace( second=0, microsecond=0) # sorting is by minute
            if last_date is not None:
                self.assertTrue(last_date <= this_date, "Date wrong: "+str(last_date)+" is not <= "+str(this_date))
                last_date = this_date
            last_date = this_date
        
    def testSentenceListSortingDescending(self):
        results = self._mc.sentenceList(ApiBaseTest.QUERY,ApiBaseTest.FILTER_QUERY,0,ApiBaseTest.SENTENCE_COUNT,
            self._mc.SORT_PUBLISH_DATE_DESC)
        self.assertEqual(len(results['response']['docs']), ApiBaseTest.SENTENCE_COUNT)
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
        results1 = self._mc.sentenceList(ApiBaseTest.QUERY,ApiBaseTest.FILTER_QUERY,0,ApiBaseTest.SENTENCE_COUNT,
            self._mc.SORT_RANDOM)
        self.assertEqual(len(results1['response']['docs']), ApiBaseTest.SENTENCE_COUNT)
        results2 = self._mc.sentenceList(ApiBaseTest.QUERY,ApiBaseTest.FILTER_QUERY,ApiBaseTest.SENTENCE_COUNT+3,ApiBaseTest.SENTENCE_COUNT,
            self._mc.SORT_RANDOM)
        self.assertEqual(len(results2['response']['docs']), ApiBaseTest.SENTENCE_COUNT)
        for idx in range(0,ApiBaseTest.SENTENCE_COUNT):
            self.assertNotEqual(results1['response']['docs'][idx]['stories_id'],results2['response']['docs'][idx]['stories_id'],
                "Stories in two different random sets are the same :-(")

    def testSentenceList(self):
        results = self._mc.sentenceList(ApiBaseTest.QUERY, ApiBaseTest.FILTER_QUERY)
        self.assertEqual(int(results['responseHeader']['status']),0)
        self.assertEqual(int(results['response']['numFound']),6713)
        self.assertEqual(len(results['response']['docs']), 1000)

    def testSentenceListPaging(self):
        # test limiting rows returned
        results = self._mc.sentenceList(ApiBaseTest.QUERY, ApiBaseTest.FILTER_QUERY,0,100)
        self.assertEqual(int(results['response']['numFound']), 6713)
        self.assertEqual(len(results['response']['docs']), 100)
        # test starting offset
        results = self._mc.sentenceList(ApiBaseTest.QUERY, ApiBaseTest.FILTER_QUERY,6700)
        self.assertEqual(int(results['response']['numFound']), 6713)
        self.assertEqual(len(results['response']['docs']), 13)

class ApiSentencesTest(ApiBaseTest):

    def testSentence(self):
        sentence_id = '3841125325'
        sentence = self._mc.sentence(sentence_id)
        self.assertEqual(sentence['story_sentences_id'],sentence_id)
        self.assertEqual(sentence['stories_id'],321728712)
        self.assertTrue(len(sentence['sentence'])>0)

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

    def testFieldCount(self):
        # regular call for sentence counts
        sentence_results = self._mc.sentenceFieldCount('obama','+media_id:1')
        self.assertFalse('stats' in sentence_results)
        self.assertFalse('counts' in sentence_results)
        self.assertTrue(len(sentence_results)>0)
        [self.assertTrue(tag['count']) for tag in sentence_results]
        # regular call for story counts
        story_results = self._mc.sentenceFieldCount('obama','+media_id:1',field='tags_id_stories')
        self.assertFalse('stats' in story_results)
        self.assertFalse('counts' in story_results)
        self.assertTrue(len(story_results)>0)
        [self.assertTrue(tag['count']) for tag in story_results]
        # compare
        self.assertTrue(len(story_results)!=len(sentence_results))
        # with stats
        results = self._mc.sentenceFieldCount('obama','+media_id:1',include_stats=True)
        self.assertTrue('stats' in results)
        self.assertTrue('counts' in results)
        # filter by tag set
        sentence_results = self._mc.sentenceFieldCount('*',tag_sets_id=TEST_TAG_SET_ID)
        self.assertTrue(len(sentence_results)>0)
        [self.assertEqual(tag['tag_sets_id'],TEST_TAG_SET_ID) for tag in sentence_results]

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

class AdminApiTaggingUpdateTest(AdminApiBaseTest):

    def testTagUpdate(self):
        example_tag_id = 9172167
        # grab the tag info
        tag = self._mc.tag(example_tag_id)
        # change the name, label and description
        result = self._mc.updateTag(example_tag_id, 'modified tag', 'modified label', 'modified description')
        modified_tag = self._mc.tag(example_tag_id)
        self.assertEqual(modified_tag['tag'],'modified tag')
        self.assertEqual(modified_tag['label'],'modified label')
        self.assertEqual(modified_tag['description'],'modified description')
        # set it back
        result = self._mc.updateTag(example_tag_id, 'example tag', 'example label', 'This is an exampel tag used in api client test scripts')
        modified_tag = self._mc.tag(example_tag_id)
        self.assertEqual(modified_tag['tag'],'example tag')
        self.assertEqual(modified_tag['label'],'example label')
        self.assertEqual(modified_tag['description'],'This is an exampel tag used in api client test scripts')

    def testTagSetUpdate(self):
        example_tag_sets_id = TEST_TAG_SET_ID
        # grab the tag info
        tag_set = self._mc.tagSet(example_tag_sets_id)
        # change the name, label and description
        result = self._mc.updateTagSet(example_tag_sets_id, TEST_USER_EMAIL, 'modified label', 'modified description')
        modified_tag = self._mc.tagSet(example_tag_sets_id)
        self.assertEqual(modified_tag['name'],TEST_USER_EMAIL)
        self.assertEqual(modified_tag['label'],'modified label')
        self.assertEqual(modified_tag['description'],'modified description')
        # set it back
        result = self._mc.updateTagSet(example_tag_sets_id, TEST_USER_EMAIL, 'rahulbot', 'The tag set of Rahul!')
        modified_tag = self._mc.tagSet(example_tag_sets_id)
        self.assertEqual(modified_tag['name'], TEST_USER_EMAIL)
        self.assertEqual(modified_tag['label'],'rahulbot')
        self.assertEqual(modified_tag['description'],'The tag set of Rahul!')

class AdminApiTaggingContentTest(AdminApiBaseTest):

    def testTagStories(self):
        test_story_id = 1
        tag_set_name = TEST_USER_EMAIL
        # tag a story with two things
        desired_tags = [ mediacloud.api.StoryTag(test_story_id, tag_set_name, 'test_tag1'),
                 mediacloud.api.StoryTag(test_story_id, tag_set_name, 'test_tag2') ] 
        response = self._mc.tagStories(desired_tags)
        self.assertEqual(len(response),len(desired_tags))
        # make sure it worked
        story = self._mc.story(test_story_id,sentences=True)
        tags_on_story = [t for t in story['story_tags'] if t['tag_set']==tag_set_name]
        self.assertEqual(len(tags_on_story),len(desired_tags))
        # now remove one
        desired_tags = [ mediacloud.api.StoryTag(1,TEST_USER_EMAIL,'test_tag1') ]
        response = self._mc.tagStories(desired_tags, clear_others=True)
        self.assertEqual(len(response),len(desired_tags))
        # and check it
        story = self._mc.story(test_story_id,sentences=True)
        tags_on_story = [t for t in story['story_tags'] if t['tag_set']==tag_set_name]
        self.assertEqual(len(tags_on_story),len(desired_tags))

    def testTagSentences(self):
        test_story_id = 150891343
        test_tag_id1 = '9172167' # mc-api-test@media.mit.edu:test_tag1
        test_tag_id2 = '9172168' # mc-api-test@media.mit.edu:test_tag2
        tag_set_name = TEST_USER_EMAIL
        # grab some sentence_ids to test with
        orig_story = self._mc.story(test_story_id,sentences=True)
        self.assertTrue( 'story_sentences' in orig_story )
        self.assertTrue( len(orig_story['story_sentences']) > 2 )
        sentence_ids = [ s['story_sentences_id'] for s in orig_story['story_sentences'][0:2] ]
        # add a tag
        desired_tags = [ mediacloud.api.SentenceTag(sid, tag_set_name, 'test_tag1') 
            for sid in sentence_ids ]
        response = self._mc.tagSentences(desired_tags)
        self.assertEqual(len(response),len(desired_tags))
        # and verify it worked
        tagged_story = self._mc.story(test_story_id,sentences=True)
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
        tagged_story = self._mc.story(test_story_id,sentences=True)
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
        tagged_story = self._mc.story(test_story_id,sentences=True)
        tagged_sentences = [ s for s in tagged_story['story_sentences'] if len(s['tags']) > 0 ]
        for s in tagged_sentences:
            if s['story_sentences_id'] in sentence_ids:
                self.assertTrue(test_tag_id1 in s['tags'])
                self.assertFalse(test_tag_id2 in s['tags'])
