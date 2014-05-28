#! /usr/bin/env python

import unittest

from mediacloud.test.apitest import *
from mediacloud.test.storagetest import *

test_classes = [
	ApiMediaTest, ApiMediaSetTest, ApiFeedsTest, ApiDashboardsTest, ApiTagsTest, ApiTagSetsTest, 
	ApiStoriesTest, ApiWordCountTest, ApiSentencesTest,
	MongoStorageTest,
	AuthTokenTest
]

for test_class in test_classes:
	suite = unittest.TestLoader().loadTestsFromTestCase(test_class)
	unittest.TextTestRunner(verbosity=2).run(suite)
