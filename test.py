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

# set up all logging to DEBUG (cause we're running tests here!)
logging.basicConfig(level=logging.DEBUG)
log_file = logging.FileHandler('mediacloud-api.log')
# set up mediacloud logging to the file
mc_logger = logging.getLogger('mediacloud-api')
mc_logger.propagate = False
mc_logger.addHandler(log_file)
# set up requests logging to the file
requests_logger = logging.getLogger('requests')
requests_logger.propagate = False
requests_logger.addHandler(log_file)

# now run all the tests
for test_class in test_classes:
	suite = unittest.TestLoader().loadTestsFromTestCase(test_class)
	unittest.TextTestRunner(verbosity=2).run(suite)
