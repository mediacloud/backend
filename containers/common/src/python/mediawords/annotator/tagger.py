import abc
from typing import Union, List

import re

from mediawords.annotator.store import JSONAnnotationStore
from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error

log = create_logger(__name__)


class McJSONAnnotationTaggerException(Exception):
    """JSON annotation tagger exception."""
    pass


class JSONAnnotationTagger(metaclass=abc.ABCMeta):
    """Abstract JSON annotation tagger role."""

    class Tag(object):
        """Single tag derived from JSON annotation."""

        __slots__ = [
            'tag_sets_name',
            'tag_sets_label',
            'tag_sets_description',

            'tags_name',
            'tags_label',
            'tags_description',
        ]

        def __init__(self,
                     tag_sets_name: str,
                     tag_sets_label: str,
                     tag_sets_description: str,
                     tags_name: str,
                     tags_label: str,
                     tags_description: str):
            """Constructor."""
            self.tag_sets_name = tag_sets_name
            self.tag_sets_label = tag_sets_label
            self.tag_sets_description = tag_sets_description
            self.tags_name = tags_name
            self.tags_label = tags_label
            self.tags_description = tags_description

    @abc.abstractmethod
    def _tags_for_annotation(self, annotation: Union[dict, list]) -> List[Tag]:
        """Returns list of tags for decoded JSON annotation."""
        raise NotImplementedError

    # ---

    __slots__ = [
        '__annotation_store',
    ]

    def __init__(self, annotation_store: JSONAnnotationStore):
        """Constructor."""

        assert annotation_store, "Annotation store is set."
        self.__annotation_store = annotation_store

    @staticmethod
    def __strip_linebreaks_and_whitespace(string: str) -> str:
        """Strip linebreaks and whitespaces for tag / tag set name (tag name can't contain linebreaks)."""

        string = re.sub(r"[\r\n]", " ", string)
        string = re.sub(r"\s\s*", " ", string)
        string = string.strip()

        return string

    def update_tags_for_story(self, db: DatabaseHandler, stories_id: int) -> None:
        """Add version, country and story tags for story."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        annotation = self.__annotation_store.fetch_annotation_for_story(db=db, stories_id=stories_id)
        if annotation is None:
            raise McJSONAnnotatorTaggerException("Unable to fetch annotation for story %d" % stories_id)

        tags = None
        try:
            tags = self._tags_for_annotation(annotation)
        except Exception as ex:
            # Programming error (should at least return an empty list)
            fatal_error("Unable to fetch tags for story %d: %s" % (stories_id, str(ex),))

        if tags is None:
            raise McJSONAnnotatorTaggerException("Returned tags is None for story %d." % stories_id)

        log.debug("Tags for story %d: %s" % (stories_id, str(tags),))

        db.begin()

        unique_tag_sets_names = set()
        for tag in tags:
            tag_sets_name = self.__strip_linebreaks_and_whitespace(tag.tag_sets_name)
            unique_tag_sets_names.add(tag_sets_name)

        # Delete old tags the story might have under a given tag set
        db.query("""
            DELETE FROM stories_tags_map
            WHERE stories_id = %(stories_id)s
              AND tags_id IN (
                SELECT tags_id
                FROM tags
                WHERE tag_sets_id IN (
                  SELECT tag_sets_id
                  FROM tag_sets
                  WHERE name = ANY(%(tag_sets_names)s)
                )
              )
        """, {'stories_id': stories_id, 'tag_sets_names': list(unique_tag_sets_names)})

        for tag in tags:
            tag_sets_name = self.__strip_linebreaks_and_whitespace(tag.tag_sets_name)
            tags_name = self.__strip_linebreaks_and_whitespace(tag.tags_name)

            # Not using find_or_create() because tag set / tag might already exist
            # with slightly different label / description

            # Find or create a tag set
            db_tag_set = db.select(table='tag_sets', what_to_select='*', condition_hash={'name': tag_sets_name}).hash()
            if db_tag_set is None:
                db.query("""
                    INSERT INTO tag_sets (name, label, description)
                    VALUES (%(name)s, %(label)s, %(description)s)
                    ON CONFLICT (name) DO NOTHING
                """, {
                    'name': tag_sets_name,
                    'label': tag.tag_sets_label,
                    'description': tag.tag_sets_description
                })
                db_tag_set = db.select(table='tag_sets',
                                       what_to_select='*',
                                       condition_hash={'name': tag_sets_name}).hash()
            tag_sets_id = int(db_tag_set['tag_sets_id'])

            # Find or create tag
            db_tag = db.select(table='tags', what_to_select='*', condition_hash={
                'tag_sets_id': tag_sets_id,
                'tag': tags_name,
            }).hash()
            if db_tag is None:
                db.query("""
                    INSERT INTO tags (tag_sets_id, tag, label, description)
                    VALUES (%(tag_sets_id)s, %(tag)s, %(label)s, %(description)s)
                    ON CONFLICT (tag, tag_sets_id) DO NOTHING
                """, {
                    'tag_sets_id': tag_sets_id,
                    'tag': tags_name,
                    'label': tag.tags_label,
                    'description': tag.tags_description,
                })
                db_tag = db.select(table='tags', what_to_select='*', condition_hash={
                    'tag_sets_id': tag_sets_id,
                    'tag': tags_name,
                }).hash()
            tags_id = int(db_tag['tags_id'])

            # Assign story to tag (if no such mapping exists yet)
            #
            # (partitioned table's INSERT trigger will take care of conflicts)
            #
            # Not using db.create() because it tests last_inserted_id, and on duplicates there would be no such
            # "last_inserted_id" set.
            db.query("""
                INSERT INTO stories_tags_map (stories_id, tags_id)
                VALUES (%(stories_id)s, %(tags_id)s)
            """, {
                'stories_id': stories_id,
                'tags_id': tags_id,
            })

        db.commit()
