#! /usr/bin/env python

import unittest, logging
import sys

from mediacloud.test.apitest import *
from mediacloud.test.storagetest import *

test_classes = [
    ApiMediaTest, ApiMediaSetTest, ApiFeedsTest, ApiDashboardsTest, ApiTagsTest, ApiTagSetsTest, 
    ApiStoriesTest, AdminApiStoriesTest, ApiWordCountTest, ApiSentencesTest, AdminApiSentencesTest,
    MongoStorageTest,
    ApiControversyTest, ApiControversyDumpTest, ApiControversyDumpTimeSliceTest,
    AuthTokenTest,
    ApiAllFieldsOptionTest,
    AdminApiTaggingContentTest, AdminApiTaggingUpdateTest
]

# set up all logging to DEBUG (cause we're running tests here!)
logging.basicConfig(level=logging.DEBUG)
log_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
log_handler = logging.FileHandler('mediacloud-api-test.log')
log_handler.setFormatter(log_formatter)
# set up mediacloud logging to the file
mc_logger = logging.getLogger('mediacloud')
mc_logger.propagate = False
mc_logger.addHandler(log_handler)
# set up requests logging to the file
requests_logger = logging.getLogger('requests')
requests_logger.propagate = False
requests_logger.addHandler(log_handler)

# now run all the tests
suites = [ unittest.TestLoader().loadTestsFromTestCase(test_class) for test_class in test_classes ]

if __name__ == "__main__":
    suite = unittest.TestSuite(suites)
    test_result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not test_result.wasSuccessful():
        sys.exit(1)
