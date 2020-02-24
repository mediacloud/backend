from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_download_for_feed

from crawler_fetcher.handlers.feed_syndicated import DownloadFeedSyndicatedHandler


def test_syndicated_guid_conflict():
    """Test what happens if multiple stories have the same GUID."""
    db = connect_to_db()

    test_feed_input = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
    <channel>
        <title>Test feed</title>
        <link>https://www.example.cpm</link>
        <description></description>
        <language>en</language>

        <item>
        
            <!-- _find_dup_story() skips the story if it either has no title or its title is "(no title)" -->
            <title>(no title)</title>
            <link>https://www.example.com/first-item/</link>
            <guid isPermaLink="false">IDENTICAL_GUID</guid>
            <description>Spiral notebooks should be avoided.</description>
            <content:encoded><p>Spiral notebooks should be avoided.</p></content:encoded>
        </item>
        <item>
            <title>(no title)</title>
            <link>https://www.example.com/second-item/</link>
            <guid isPermaLink="false">IDENTICAL_GUID</guid>
            <description>Spiral notebooks should be avoided.</description>
            <content:encoded><p>Spiral notebooks should be avoided.</p></content:encoded>
        </item>
    </channel>
</rss>"""

    test_output = {
        'media_id': 1,
        'stories_id': 1,
        'url': 'https://www.example.com/first-item/',
        'title': '(no title)',
        'guid': 'IDENTICAL_GUID',
        'description': '<p>Spiral notebooks should be avoided.</p>',
        'full_text_rss': False,
        'language': None,
    }

    test_medium = create_test_medium(db=db, label='downloads test')
    test_feed = create_test_feed(db, label='downloads test', medium=test_medium)
    test_download_feed = create_download_for_feed(db=db, feed=test_feed)

    handler = DownloadFeedSyndicatedHandler()
    new_story_ids = handler.add_stories_from_feed(
        db=db,
        download=test_download_feed,
        content=test_feed_input,
    )
    assert new_story_ids

    stories = []
    for stories_id in new_story_ids:
        stories.append(db.find_by_id(table='stories', object_id=stories_id))

    stories = [
        {k: v for k, v in d.items() if k not in {'publish_date', 'collect_date', 'normalized_title_hash'}}
        for d in stories
    ]

    print(f"Got stories: {stories}")

    assert stories == [test_output]
