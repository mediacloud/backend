#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.util.colors import get_consistent_color


def test_get_consistent_color_create():
    db = connect_to_db()

    item_set = 'test_set'
    unique_color_mapping = dict()

    # Test if helper is able to create new colors when it runs out of hardcoded set
    for x in range(50):
        item_id = 'color-%d' % x
        color = get_consistent_color(db=db, item_set=item_set, item_id=item_id)
        assert len(color) == len('ffffff')
        unique_color_mapping[item_id] = color

    # Make sure the first color is from the Media Cloud color palette
    assert unique_color_mapping['color-0'] == '1f77b4'

    # Make sure that if we run it again, we'll get the same colors
    for x in range(50):
        item_id = 'color-%d' % x
        color = get_consistent_color(db=db, item_set=item_set, item_id=item_id)
        assert len(color) == len('ffffff')
        assert unique_color_mapping[item_id] == color
