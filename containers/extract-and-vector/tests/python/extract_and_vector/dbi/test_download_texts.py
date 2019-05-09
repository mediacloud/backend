from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_download_for_feed
from extract_and_vector.dbi.download_texts import create


def test_create():
    db = connect_to_db()

    test_medium = create_test_medium(db, 'downloads test')
    test_feed = create_test_feed(db, 'downloads test', test_medium)
    test_download = create_download_for_feed(db, test_feed)

    test_download['path'] = 'postgresql:foo'
    test_download['state'] = 'success'
    db.update_by_id('downloads', test_download['downloads_id'], test_download)

    assert len(db.query("""
        SELECT *
        FROM download_texts
        WHERE downloads_id = %(downloads_id)s
    """, {'downloads_id': test_download['downloads_id']}).hashes()) == 0

    assert len(db.query("""
        SELECT *
        FROM downloads
        WHERE downloads_id = %(downloads_id)s
          AND extracted = 't'
    """, {'downloads_id': test_download['downloads_id']}).hashes()) == 0

    extract = {
        'extracted_text': 'Hello!',
    }

    created_download_text = create(db=db, download=test_download, extract=extract)
    assert created_download_text
    assert created_download_text['downloads_id'] == test_download['downloads_id']

    found_download_texts = db.query("""
        SELECT *
        FROM download_texts
        WHERE downloads_id = %(downloads_id)s
    """, {'downloads_id': test_download['downloads_id']}).hashes()
    assert len(found_download_texts) == 1

    download_text = found_download_texts[0]
    assert download_text
    assert download_text['downloads_id'] == test_download['downloads_id']
    assert download_text['download_text'] == extract['extracted_text']
    assert download_text['download_text_length'] == len(extract['extracted_text'])
