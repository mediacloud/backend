# noinspection PyProtectedMember
from mediawords.solr import _get_stories_ids_from_stories_only_params as gsifsop


def test_solr_stories_only_query():
    assert gsifsop({'q': ''}) is None, 'Empty "q"'
    assert gsifsop({'fq': ''}) is None, 'Empty "fq"'
    assert gsifsop({'q': '', 'fq': ''}) is None, 'Empty "q" and "fq"'

    assert gsifsop({'q': 'stories_id:1'}) == [1], 'Simple "q" match'
    assert gsifsop({'q': 'media_id:1'}) is None, 'Simple "q" miss'
    assert gsifsop({'q': '*:*', 'fq': 'stories_id:1'}) == [1], 'Simple "fq" match'
    assert gsifsop({'q': '*:*', 'fq': 'media_id:1'}) is None, 'Simple "fq" miss'

    assert gsifsop({'q': 'media_id:1', 'fq': 'stories_id:1'}) is None, '"q" hit / "fq" miss'
    assert gsifsop({'q': 'stories_id:1', 'fq': 'media_id:1'}) is None, '"q" miss / "fq" hit'

    assert gsifsop({'q': '*:*', 'fq': ['stories_id:1', 'stories_id:1']}) == [1], '"fq" list hit'
    assert gsifsop({'q': '*:*', 'fq': ['stories_id:1', 'media_id:1']}) is None, '"fq" list miss'

    assert gsifsop({'q': 'stories_id:1', 'fq': ''}) == [1], '"q" hit / empty "fq"'
    assert gsifsop({'q': 'stories_id:1', 'fq': []}) == [1], '"q" hit / empty "fq" list'
    assert gsifsop({'q': '*:*', 'fq': 'stories_id:1'}) == [1], '"*:*" "q" / "fq" hit'
    assert gsifsop({'fq': 'stories_id:1'}) is None, 'Empty "q", "fq" hit'
    assert gsifsop({'q': '*:*'}) is None, '*:* "q"'

    assert set(gsifsop({'q': 'stories_id:( 1 2 3 )'})) == {1, 2, 3}, '"q" list'
    assert set(gsifsop({
        'q': 'stories_id:( 1 2 3 )', 'fq': 'stories_id:( 1 3 4 )'
    })) == {1, 3}, '"q" list / "fq" list intersection'
    assert gsifsop({'q': '( stories_id:2 )'}) == [2], '"q" parens'
    assert gsifsop({'q': '(stories_id:3)'}) == [3], '"q" parens no spaces'

    assert gsifsop({'q': 'stories_id:4 and stories_id:4'}) == [4], '"q" simple "and"'
    assert set(gsifsop({'q': 'stories_id:( 1 2 3 ) and stories_id:( 2 3 4 )'})) == {2, 3}, '"q" and intersection'
    assert gsifsop({'q': 'stories_id:( 1 2 3 ) and stories_id:( 4 5 6 )'}) == [], '"q" and empty intersection'

    assert set(gsifsop({
        'q': 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and stories_id:( 3 4 ) )'
    })) == {3, 4}, '"q" complex "and" intersection'

    assert gsifsop({
        'q': 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and media_id:1 )'
    }) is None, '"q" complex "and" intersection miss'
    assert gsifsop({
        'q': 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and stories_id:( 243 ) )'
    }) == [], '"q" complex "and" intersection empty'
    assert set(gsifsop({
        'q': 'stories_id:( 1 2 3 4 ) and stories_id:( 2 3 4 5 6 ) and stories_id:( 3 4 )'
    })) == {3, 4}, '"q" complex "and" intersection'

    assert gsifsop({
        'q': 'stories_id:1 and ( stories_id:2 and ( stories_id:3 and obama ) )'
    }) is None, '"q" complex boolean query with buried miss'
    assert gsifsop({
        'q': '( ( stories_id:1 or stories_id:2 ) and stories_id:3 )'
    }) is None, '"q" complex boolean query with buried "or"'

    assert gsifsop({'q': 'stories_id:( 1 2 3 4 5 6 )', 'foo': 'bar'}) is None, 'Unrecognized parameters'
    assert set(gsifsop({'q': 'stories_id:( 1 2 3 4 5 6 )', 'start': '2'})) == {3, 4, 5, 6}, '"start" parameter'
    assert set(gsifsop({
        'q': 'stories_id:( 1 2 3 4 5 6 )',
        'start': '2',
        'rows': 2,
    })) == {3, 4}, '"start" and "rows" parameters'
    assert set(gsifsop({'q': 'stories_id:( 1 2 3 4 5 6 )', 'rows': 2})) == {1, 2}, '"rows" parameter'
