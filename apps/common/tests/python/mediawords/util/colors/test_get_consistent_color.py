from mediawords.db import connect_to_db
from mediawords.util.colors import get_consistent_color


def test_get_consistent_color():

    db = connect_to_db()

    color_c_baz = get_consistent_color(db=db, item_set='c', item_id='baz')
    color_b_baz = get_consistent_color(db=db, item_set='b', item_id='baz')
    color_b_bar = get_consistent_color(db=db, item_set='b', item_id='bar')
    color_a_baz = get_consistent_color(db=db, item_set='a', item_id='baz')
    color_a_bar = get_consistent_color(db=db, item_set='a', item_id='bar')
    color_a_foo = get_consistent_color(db=db, item_set='a', item_id='foo')

    num_db_colors = db.query("SELECT COUNT(*) FROM color_sets").flat()
    assert num_db_colors[0] == 9

    assert color_a_foo != color_a_bar
    assert color_a_foo != color_a_baz
    assert color_a_bar != color_a_baz
    assert color_b_bar != color_b_baz

    color_a_foo_2 = get_consistent_color(db=db, item_set='a', item_id='foo')
    color_a_bar_2 = get_consistent_color(db=db, item_set='a', item_id='bar')
    color_a_baz_2 = get_consistent_color(db=db, item_set='a', item_id='baz')
    color_b_bar_2 = get_consistent_color(db=db, item_set='b', item_id='bar')
    color_b_baz_2 = get_consistent_color(db=db, item_set='b', item_id='baz')
    color_c_baz_2 = get_consistent_color(db=db, item_set='c', item_id='baz')

    assert color_a_foo_2 == color_a_foo
    assert color_a_bar_2 == color_a_bar
    assert color_a_baz_2 == color_a_baz
    assert color_b_bar_2 == color_b_bar
    assert color_b_baz_2 == color_b_baz
    assert color_c_baz_2 == color_c_baz
