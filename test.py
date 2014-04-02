#! /usr/bin/env python

import unittest

from mediacloud.test.apitest import ApiMediaTest, ApiMediaSetTest, ApiFeedsTest, ApiDashboardsTest, ApiTagsTest, ApiTagSetsTest, ApiStoriesTest, ApiWordCountTest, ApiSentencesTest
from mediacloud.test.storagetest import CouchStorageTest, MongoStorageTest

test_classes = [
	ApiMediaTest, ApiMediaSetTest, ApiFeedsTest, ApiDashboardsTest, ApiTagsTest, ApiTagSetsTest, 
	ApiStoriesTest, ApiWordCountTest, ApiSentencesTest,
	CouchStorageTest, MongoStorageTest
]

for test_class in test_classes:
	suite = unittest.TestLoader().loadTestsFromTestCase(test_class)
	unittest.TextTestRunner(verbosity=1).run(suite)
