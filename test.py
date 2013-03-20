#! /usr/bin/env python

import unittest

from mediacloud.test.apitest import ApiTest
from mediacloud.test.storagetest import CouchStorageTest
from mediacloud.test.storagetest import MongoStorageTest
from mediacloud.test.examplestest import ExamplesTest

suite = unittest.TestLoader().loadTestsFromTestCase(CouchStorageTest)
unittest.TextTestRunner(verbosity=2).run(suite)

suite = unittest.TestLoader().loadTestsFromTestCase(MongoStorageTest)
unittest.TextTestRunner(verbosity=2).run(suite)

suite = unittest.TestLoader().loadTestsFromTestCase(ExamplesTest)
unittest.TextTestRunner(verbosity=2).run(suite)

suite = unittest.TestLoader().loadTestsFromTestCase(ApiTest)
unittest.TextTestRunner(verbosity=2).run(suite)
