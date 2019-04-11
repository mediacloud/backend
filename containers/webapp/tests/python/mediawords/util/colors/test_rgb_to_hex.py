#!/usr/bin/env py.test

from mediawords.util.colors import rgb_to_hex


def test_rgb_to_hex():
    assert rgb_to_hex(255, 0, 0).lower() == 'ff0000'
    assert rgb_to_hex(0, 0, 0).lower() == '000000'
    assert rgb_to_hex(255, 255, 255).lower() == 'ffffff'
