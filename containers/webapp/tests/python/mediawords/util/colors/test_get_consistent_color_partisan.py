#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.util.colors import get_consistent_color


def test_get_consistent_color_partisan():
    """Colors that "color_sets" were pre-filled with in mediawords.sql."""

    db = connect_to_db()

    partisan_colors = {
        'partisan_2012_conservative': 'c10032',
        'partisan_2012_liberal': '00519b',
        'partisan_2012_libertarian': '009543',
    }

    for color_id, color in partisan_colors.items():
        got_color = get_consistent_color(db=db, item_set='partisan_code', item_id=color_id)
        assert got_color == color
