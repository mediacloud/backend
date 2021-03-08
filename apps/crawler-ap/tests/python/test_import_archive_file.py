from mediawords.db import connect_to_db
from mediawords.util.log import create_logger

from crawler_ap.ap import import_archive_file, AP_MEDIUM_NAME

log = create_logger(__name__)


def test_import_archive_file():
    db = connect_to_db()

    db.create('media', {'url': 'ap.com', 'name': AP_MEDIUM_NAME})

    xml_file = '/opt/mediacloud/tests/data/ap_test_fixtures/test_ap_fixture_archive.xml'

    import_archive_file(db, xml_file)

    stories = db.query("select * from stories").hashes()

    assert len(stories) == 1

    story = stories[0]

    assert story['title'] == 'Report: Far-right violence in Germany declined in 2017'
    assert story['url'] == 'https://apnews.com/61a17439ecd940498124a2939a78c678'
    assert story['guid'] == 'de9a436b796b41d5821509773f740fa0'
    assert story['publish_date'] == '2018-07-06 13:34:25'
    assert story['description'][0:10] == 'German media are reporting a drop'[0:10]

    download_text = db.query("select * from download_texts").hash()

    assert download_text['download_text'][0:10] == 'BERLIN (AP'
