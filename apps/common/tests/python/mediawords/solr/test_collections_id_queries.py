from typing import List, Dict, Any

from mediawords.db import connect_to_db, DatabaseHandler
# noinspection PyProtectedMember
from mediawords.solr import _insert_collection_media_ids
from mediawords.test.db.create import create_test_medium


def __verify_collections_id_result(db: DatabaseHandler, tags: List[Dict[str, Any]], label: str) -> None:
    tags_ids = [str(_['tags_id']) for _ in tags]

    if len(tags_ids) > 1:
        q_arg = f"({' '.join(tags_ids)})"
        q_or_arg = f"({' or '.join(tags_ids)})"
    else:
        q_arg = tags_ids[0]
        q_or_arg = None

    expected_media_ids = []
    for tag in tags:
        for medium in tag['media']:
            expected_media_ids.append(medium['media_id'])

    expected_q = f"media_id:({' '.join([str(_) for _ in expected_media_ids])})"

    got_q = _insert_collection_media_ids(db=db, q=f"tags_id_media:{q_arg}")
    assert expected_q == got_q, f"{label}: tags_id_media"

    got_q = _insert_collection_media_ids(db=db, q=f"collections_id:{q_arg}")
    assert expected_q == got_q, f"{label}: collections_id"

    if q_or_arg:
        got_q = _insert_collection_media_ids(db=db, q=f"collections_id:{q_or_arg}")
        assert expected_q == got_q, f'{label}: collections_id with "or"s'


def test_collections_id_queries():
    db = connect_to_db()

    num_tags = 10
    num_media_per_tag = 10

    tag_set = db.create(table='tag_sets', insert_hash={'name': 'test'})

    tags = []

    for tag_i in range(1, num_tags + 1):
        tag = db.create(table='tags', insert_hash={'tag_sets_id': tag_set['tag_sets_id'], 'tag': f"test_{tag_i}"})

        tag['media'] = []

        for medium_i in range(1, num_media_per_tag + 1):
            medium = create_test_medium(db=db, label=f"tag {tag_i} medium {medium_i}")
            db.query("""
                INSERT INTO media_tags_map (tags_id, media_id)
                VALUES (%(tags_id)s, %(media_id)s)
            """, {
                'tags_id': tag['tags_id'],
                'media_id': medium['media_id'],
            })
            tag['media'].append(medium)

        tags.append(tag)

    __verify_collections_id_result(db=db, tags=[tags[0]], label='Single "tags_id"')
    __verify_collections_id_result(db=db, tags=tags, label='All tags')
    __verify_collections_id_result(db=db, tags=tags[:3], label='Three tags')
