from mediawords.test.db.create import create_test_story_stack, create_test_topic
from mediawords.util.url import urls_are_equal
from mediawords.util.url.variants import all_url_variants
from mediawords.util.url.variants.setup_test_url_variants import TestURLVariantsTestCase


class TestGetTopicURLVariants(TestURLVariantsTestCase):

    def test_get_topic_url_variants(self):
        media = create_test_story_stack(
            db=self.db,
            data={
                'A': {
                    'B': [1, 2, 3],
                    'C': [4, 5, 6],
                },
                'D': {
                    'E': [7, 8, 9],
                }
            }
        )

        story_1 = media['A']['feeds']['B']['stories']['1']
        story_2 = media['A']['feeds']['B']['stories']['2']
        story_3 = media['A']['feeds']['B']['stories']['3']
        story_4 = media['A']['feeds']['C']['stories']['4']

        self.db.query("""
            INSERT INTO topic_merged_stories_map (source_stories_id, target_stories_id)
            VALUES (%(source_stories_id)s, %(target_stories_id)s)
        """, {
            'source_stories_id': story_2['stories_id'],
            'target_stories_id': story_1['stories_id'],
        })

        self.db.query("""
            INSERT INTO topic_merged_stories_map (source_stories_id, target_stories_id)
            VALUES (%(source_stories_id)s, %(target_stories_id)s)
        """, {
            'source_stories_id': story_3['stories_id'],
            'target_stories_id': story_2['stories_id'],
        })

        self.db.create(
            table='tag_sets',
            insert_hash={'name': 'foo'},
        )

        topic = create_test_topic(db=self.db, label='foo')

        self.db.create(
            table='topic_stories',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_4['stories_id'],
            }
        )

        self.db.create(
            table='topic_stories',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_1['stories_id'],
            }
        )

        self.db.create(
            table='topic_links',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_4['stories_id'],
                'ref_stories_id': story_1['stories_id'],
                'url': story_1['url'],
                'redirect_url': story_1['url'] + "/redirect_url",
            }
        )

        self.db.create(
            table='topic_stories',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_2['stories_id'],
            }
        )

        self.db.create(
            table='topic_links',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_4['stories_id'],
                'ref_stories_id': story_2['stories_id'],
                'url': story_2['url'],
                'redirect_url': story_2['url'] + "/redirect_url",
            }
        )

        self.db.create(
            table='topic_stories',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_3['stories_id']
            }
        )

        self.db.create(
            table='topic_links',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_4['stories_id'],
                'ref_stories_id': story_3['stories_id'],
                'url': story_3['url'] + '/alternate',
            }
        )

        test_url = story_1['url'] + self.CRUFT

        expected_urls = {
            story_1['url'],
            story_1['url'] + self.CRUFT,
            story_2['url'],
            story_1['url'] + "/redirect_url",
            story_2['url'] + "/redirect_url",
            story_3['url'],
            story_3['url'] + "/alternate",
        }

        url_variants = all_url_variants(db=self.db, url=test_url)

        assert len(expected_urls) == len(url_variants)

        sorted_expected_urls = sorted(expected_urls)
        sorted_url_variants = sorted(url_variants)

        for i in range(len(sorted_expected_urls)):
            assert urls_are_equal(url1=sorted_expected_urls[i], url2=sorted_url_variants[i])
