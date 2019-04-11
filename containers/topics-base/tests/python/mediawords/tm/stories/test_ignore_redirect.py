#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.util.url import normalize_url_lossy

from mediawords.tm.media import generate_medium_url_and_name_from_url
from mediawords.tm.stories import ignore_redirect


def test_ignore_redirect():
    """Test mediawords.tm.stories.ignore_redirect()."""
    db = connect_to_db()

    # redirect_url = None
    assert not ignore_redirect(db, 'http://foo.com', None)

    # url = redirect_url
    assert not ignore_redirect(db, 'http://foo.com', 'http://foo.com')

    # empty topic_ignore_redirects
    assert not ignore_redirect(db, 'http://foo.com', 'http://bar.com')

    # match topic_ingnore_redirects
    redirect_url = 'http://foo.com/foo.bar'
    medium_url = generate_medium_url_and_name_from_url(redirect_url)[0]
    nu = normalize_url_lossy(medium_url)

    db.create('topic_ignore_redirects', {'url': nu})

    assert ignore_redirect(db, 'http://bar.com', redirect_url)

    # no match
    assert not ignore_redirect(db, 'http://bar.com', 'http://bat.com')
