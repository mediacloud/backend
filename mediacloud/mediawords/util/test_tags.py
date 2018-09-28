from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.tags import lookup_tag


class TestTags(TestDatabaseWithSchemaTestCase):

    def test_lookup_tag(self):
        test_tag_set_name = 'test tag set'
        test_tag_name = 'test tag'

        tag_set = self.db().create(table='tag_sets', insert_hash={'name': test_tag_set_name})
        tag = self.db().create(table='tags', insert_hash={'tag': test_tag_name, 'tag_sets_id': tag_set['tag_sets_id']})

        # Invalid params
        # noinspection PyTypeChecker
        assert lookup_tag(db=self.db(), tag_name=None) is None
        assert lookup_tag(db=self.db(), tag_name='foo') is None
        assert lookup_tag(db=self.db(), tag_name='foo:bar:baz') is None

        # Nonexistent tag
        assert lookup_tag(db=self.db(), tag_name='does not:exist') == {}

        # Existent tag
        found_tag = lookup_tag(db=self.db(), tag_name='{}:{}'.format(test_tag_set_name, test_tag_name))
        assert found_tag
        assert found_tag['tags_id'] == tag['tags_id']
