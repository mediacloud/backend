from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium
from topics_base.media import guess_medium, URL_SPIDERED_SUFFIX, get_spidered_tag


def test_guess_medium() -> None:
    """Test guess_medium()."""
    db = connect_to_db()

    num_media = 5
    [create_test_medium(db, str(i)) for i in range(num_media)]

    # the default test media do not have unique domains
    # noinspection SqlWithoutWhere
    db.query("update media set url = 'http://media-' || media_id ||'.com'")

    # dummy guess_medium call to assign normalized_urls
    guess_medium(db, 'foo')

    media = db.query("select * from media order by media_id").hashes()

    # basic lookup of existing media
    assert guess_medium(db, media[0]['url']) == media[0]
    assert guess_medium(db, media[1]['url'] + '/foo/bar/') == media[1]
    assert guess_medium(db, media[2]['url'] + URL_SPIDERED_SUFFIX) == media[2]

    # create a new medium
    new_medium_story_url = 'http://new-medium.com/with/path'
    new_medium = guess_medium(db, new_medium_story_url)
    assert new_medium['name'] == 'new-medium.com'
    assert new_medium['url'] == 'http://new-medium.com/'

    spidered_tag = get_spidered_tag(db)
    spidered_mtm = db.query(
        "select * from media_tags_map where tags_id = %(a)s and media_id = %(b)s",
        {'a': spidered_tag['tags_id'], 'b': new_medium['media_id']})
    assert spidered_mtm is not None

    # find the url with some url varients
    new_medium_url_variants = [
        'http://new-medium.com/with/another/path',
        'http://www.new-medium.com/',
        'http://new-medium.com/with/path#andanchor'
    ]

    for url in new_medium_url_variants:
        assert guess_medium(db, url)['media_id'] == new_medium['media_id']

    # set foreign_rss_links to true to make guess_medium create another new medium
    db.query("update media set foreign_rss_links = 't' where media_id = %(a)s", {'a': new_medium['media_id']})

    another_new_medium = guess_medium(db, new_medium_story_url)
    assert another_new_medium['media_id'] > new_medium['media_id']
    assert another_new_medium['url'] == new_medium_story_url
    assert another_new_medium['name'] == 'http://new-medium.com/'

    # now try finding a dup
    db.query(
        "update media set dup_media_id = %(a)s where media_id = %(b)s",
        {'a': media[0]['media_id'], 'b': media[1]['media_id']})

    assert guess_medium(db, media[1]['url'])['media_id'] == media[0]['media_id']
