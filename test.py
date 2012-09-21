#! /usr/bin/env python

import unittest

from mediacloud.test.unit import ApiTest

suite = unittest.TestLoader().loadTestsFromTestCase(ApiTest)
unittest.TextTestRunner(verbosity=2).run(suite)
