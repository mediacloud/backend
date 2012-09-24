#! /usr/bin/env python

import unittest

from mediacloud.test.api import ApiTest
from mediacloud.test.storage import StorageTest

suite = unittest.TestLoader().loadTestsFromTestCase(ApiTest)
unittest.TextTestRunner(verbosity=2).run(suite)

suite = unittest.TestLoader().loadTestsFromTestCase(StorageTest)
unittest.TextTestRunner(verbosity=2).run(suite)
