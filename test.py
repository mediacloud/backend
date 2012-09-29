#! /usr/bin/env python

import unittest

from mediacloud.test.apitest import ApiTest
from mediacloud.test.storagetest import StorageTest
from mediacloud.test.examplestest import ExamplesTest

suite = unittest.TestLoader().loadTestsFromTestCase(ApiTest)
unittest.TextTestRunner(verbosity=2).run(suite)

suite = unittest.TestLoader().loadTestsFromTestCase(StorageTest)
unittest.TextTestRunner(verbosity=2).run(suite)

suite = unittest.TestLoader().loadTestsFromTestCase(ExamplesTest)
unittest.TextTestRunner(verbosity=2).run(suite)
