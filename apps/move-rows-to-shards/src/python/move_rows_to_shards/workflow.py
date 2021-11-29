from typing import List

# noinspection PyPackageRequirements
from temporal.workflow import Workflow

from mediawords.db import connect_to_db_or_raise
from mediawords.util.log import create_logger
from mediawords.workflow.exceptions import McProgrammingError, McTransientError, McPermanentError

from .workflow_interface import MoveRowsToShardsWorkflow, MoveRowsToShardsActivities

log = create_logger(__name__)


# noinspection SqlResolve,SqlNoDataSourceInspection
class MoveRowsToShardsActivitiesImpl(MoveRowsToShardsActivities):
    """Activities implementation."""

    async def max_column_value(self, table: str, id_column: str) -> int:
        if '.' not in table:
            raise McProgrammingError(f"Table name must contain schema: {table}")
        if not table.startswith('unsharded_'):
            raise McProgrammingError(f"Table name must start with 'unsharded_': {table}")
        if '.' in id_column:
            raise McProgrammingError(f"Invalid ID column name: {id_column}")

        db = connect_to_db_or_raise()

        max_id = db.query(f"""
            SELECT MAX({id_column})
            FROM {table}
        """).flat()[0]
        return max_id

    async def move_chunk_of_rows(self,
                                 src_table: str,
                                 src_columns: List[str],
                                 src_id_column: str,
                                 src_id_start: int,
                                 src_id_end: int,
                                 dst_table: str,
                                 dst_columns: List[str],
                                 dst_extra_clause: str) -> None:
        if '.' not in src_table:
            raise McProgrammingError(f"Source table name must contain schema: {src_table}")
        if not src_table.startswith('unsharded_'):
            raise McProgrammingError(f"Source table name must start with 'unsharded_': {src_table}")
        if '.' not in dst_table:
            raise McProgrammingError(f"Destination table name must contain schema: {dst_table}")
        if not dst_table.startswith('sharded_'):
            raise McProgrammingError(f"Destination schema name must start with 'sharded_': {dst_table}")
        if '.' in src_id_column:
            raise McProgrammingError(f"Invalid source ID column name: {src_id_column}")
        if len(src_columns) != len(dst_columns):
            raise McProgrammingError(
                f"Source and destination must have same amount of columns: {src_columns} {dst_columns}"
            )
        if src_id_start >= src_id_end:
            raise McProgrammingError(f"Start ID must be smaller than end ID: {src_id_start} {src_id_end}")

        db = connect_to_db_or_raise()

        log.info(
            f"Moving rows from '{src_table}' to '{dst_table}' ({src_id_column} BETWEEN {src_id_start} AND {src_id_end})"
        )

        # Disable triggers so that, for example, stories don't get reimported
        log.debug(f"Disabling triggers...")
        db.query('SET session_replication_role = replica')

        sql = f"""
            WITH deleted_rows AS (
                DELETE FROM {src_table}
                WHERE {src_id_column} BETWEEN {src_id_start} AND {src_id_end}
                RETURNING {', '.join(src_columns)}
            )
            INSERT INTO {dst_table} ({', '.join(src_columns)})
                SELECT {', '.join(dst_columns)}
                FROM deleted_rows
            {dst_extra_clause}
        """
        log.debug(f"SQL that I'm about to execute: {sql}")
        db.query(sql)

        log.debug(f"Reenabling triggers...")
        db.query('SET session_replication_role = DEFAULT')

        log.info(
            f"Moved rows from '{src_table}' to '{dst_table}' ({src_id_column} BETWEEN {src_id_start} AND {src_id_end})"
        )

    async def truncate_if_empty(self, table: str) -> None:
        if '.' not in table:
            raise McProgrammingError(f"Table name must contain schema: {table}")
        if not table.startswith('unsharded_'):
            raise McProgrammingError(f"Table name must start with 'unsharded_': {table}")

        db = connect_to_db_or_raise()

        table_has_rows = db.query(f"""
            SELECT *
            FROM {table}
            LIMIT 1
        """).flat()
        if len(table_has_rows) > 0:
            raise McProgrammingError(f"Table is still not empty")

        db.query(f"TRUNCATE {table}")


class MoveRowsToShardsWorkflowImpl(MoveRowsToShardsWorkflow):
    """Workflow implementation."""

    def __init__(self):
        self.activities: MoveRowsToShardsActivities = Workflow.new_activity_stub(
            activities_cls=MoveRowsToShardsActivities,
            # No retry_parameters here as they get set individually in @activity_method()
        )

    def _move_generic_table_rows(self,
                                 src_table: str,
                                 src_id_column: str,
                                 dst_table: str,
                                 chunk_size: int,
                                 src_columns: List[str],
                                 dst_columns: List[str],
                                 schema: str = 'public',
                                 dst_extra_clause: str = '') -> None:
        unsharded_table = f"unsharded_{schema}.{src_table}"
        sharded_table = f"sharded_{schema}.{dst_table}"

        max_id = await self.activities.max_column_value(unsharded_table, src_id_column)

        for start_id in range(1, max_id + chunk_size, chunk_size):
            end_id = start_id + chunk_size
            await self.activities.move_chunk_of_rows(
                unsharded_table,
                src_columns,
                src_id_column,
                start_id,
                end_id,
                sharded_table,
                dst_columns,
                dst_extra_clause,
            )

        await self.activities.truncate_if_empty(unsharded_table)

    def _move_generic_table_rows_pkey(self,
                                      table: str,
                                      chunk_size: int,
                                      src_columns_sans_pkey: List[str],
                                      dst_columns_sans_pkey: List[str],
                                      schema: str = 'public',
                                      dst_extra_clause: str = '') -> None:
        # Same ID column name on both source and destination tables
        id_column = f"{table}_id"

        self._move_generic_table_rows(
            src_table=table,
            dst_table=table,
            src_id_column=id_column,
            chunk_size=chunk_size,
            src_columns=[id_column] + src_columns_sans_pkey,
            dst_columns=[f'{id_column}::BIGINT'] + dst_columns_sans_pkey,
            schema=schema,
            dst_extra_clause=dst_extra_clause,
        )

    async def move_rows_to_shards(self) -> None:
        self._move_generic_table_rows_pkey(
            table='auth_user_request_daily_counts',
            # 338,454,970 rows in source table; 17 chunks
            chunk_size=20_000_000,
            src_columns_sans_pkey=[
                'email',
                'day',
                'requests_count',
                'requested_items_count',
            ],
            dst_columns_sans_pkey=[
                'email',
                'day',
                'requests_count::BIGINT',
                'requested_items_count::BIGINT',
            ],
            dst_extra_clause='ON CONFLICT (email, day) DO NOTHING',
        )

        self._move_generic_table_rows_pkey(
            table='media_stats',
            # 89,970,140 in source table; 9 chunks
            chunk_size=10_000_000,
            src_columns_sans_pkey=[
                'media_stats_id',
                'media_id',
                'num_stories',
                'num_sentences',
                'stat_date',
            ],
            dst_columns_sans_pkey=[
                'media_stats_id::BIGINT',
                'media_id::BIGINT',
                'num_stories::BIGINT',
                'num_sentences::BIGINT',
                'stat_date',
            ],
            dst_extra_clause='ON CONFLICT (media_id, stat_date) DO NOTHING',
        )

        self._move_generic_table_rows(
            src_table='media_coverage_gaps',
            dst_table='media_coverage_gaps',
            src_id_column='media_id',
            # MAX(media_id) = 1,892,933; 63,132,122 rows in source table; 19 chunks
            chunk_size=100_000,
            src_columns=[
                'media_id',
                'stat_week',
                'num_stories',
                'expected_stories',
                'num_sentences',
                'expected_sentences',
            ],
            dst_columns=[
                'media_id::BIGINT',
                'stat_week',
                'num_stories',
                'expected_stories',
                'num_sentences',
                'expected_sentences',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='stories',
            # 2,119,319,121 in source table; 43 chunks
            chunk_size=50_000_000,
            src_columns_sans_pkey=[
                'media_id',
                'url',
                'guid',
                'title',
                'normalized_title_hash',
                'description',
                'publish_date',
                'collect_date',
                'full_text_rss',
                'language',
            ],
            dst_columns_sans_pkey=[
                'media_id::BIGINT',
                'url::TEXT',
                'guid::TEXT',
                'title',
                'normalized_title_hash',
                'description',
                'publish_date',
                'collect_date',
                'full_text_rss',
                'language',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='stories_ap_syndicated',
            # 1,715,725,719 in source table; 35 chunks
            chunk_size=50_000_000,
            src_columns_sans_pkey=[
                'stories_id',
                'ap_syndicated',
            ],
            dst_columns_sans_pkey=[
                'stories_id::BIGINT',
                'ap_syndicated',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='story_urls',
            # 2,223,082,697 in source table; 45 chunks
            chunk_size=50_000_000,
            src_columns_sans_pkey=[
                'stories_id',
                'url',
            ],
            dst_columns_sans_pkey=[
                'stories_id::BIGINT',
                'url::TEXT',
            ],
        )

        self._move_generic_table_rows(
            src_table='feeds_stories_map_p',
            dst_table='feeds_stories_map',
            src_id_column='feeds_stories_map_p_id',
            # 2,075,474,945 in source table; 42 chunks
            chunk_size=50_000_000,
            src_columns=[
                'feeds_stories_map_p_id AS feeds_stories_map_id',
                'feeds_id',
                'stories_id',
            ],
            dst_columns=[
                'feeds_stories_map_id::BIGINT',
                'feeds_id::BIGINT',
                'stories_id::BIGINT',
            ],
        )

        self._move_generic_table_rows(
            src_table='stories_tags_map_p',
            dst_table='stories_tags_map',
            src_id_column='stories_tags_map_p_id',
            # 15,909,175,961 in source table; 32 chunks
            chunk_size=500_000_000,
            src_columns=[
                'stories_tags_map_p_id AS stories_tags_map_id',
                'stories_id',
                'tags_id',
            ],
            dst_columns=[
                'stories_tags_map_id::BIGINT',
                'stories_id::BIGINT',
                'tags_id::BIGINT',
            ],
        )

        self._move_generic_table_rows(
            src_table='story_sentences_p',
            dst_table='story_sentences',
            src_id_column='story_sentences_p_id',
            # 44,738,767,120 in source table; 90 chunks
            chunk_size=500_000_000,
            src_columns=[
                'story_sentences_p_id AS story_sentences_id',
                'stories_id',
                'sentence_number',
                'sentence',
                'media_id',
                'publish_date',
                'language',
                'is_dup',
            ],
            dst_columns=[
                'story_sentences_id::BIGINT',
                'stories_id::BIGINT',
                'sentence_number',
                'sentence',
                'media_id::BIGINT',
                'publish_date',
                'language',
                'is_dup',
            ],
        )

        self._move_generic_table_rows(
            src_table='solr_import_stories',
            dst_table='solr_import_stories',
            src_id_column='stories_id',
            # Really small table, can copy everything in one go; 3 chunks
            chunk_size=1_000_000_000,
            src_columns=[
                'stories_id',
            ],
            dst_columns=[
                'stories_id::BIGINT',
            ],
            dst_extra_clause='ON CONFLICT (stories_id) DO NOTHING',
        )

        self._move_generic_table_rows(
            src_table='solr_imported_stories',
            dst_table='solr_imported_stories',
            src_id_column='stories_id',
            # MAX(stories_id) = 2,119,343,981; 43 chunks
            chunk_size=50_000_000,
            src_columns=[
                'stories_id',
                'import_date',
            ],
            dst_columns=[
                'stories_id::BIGINT',
                'import_date',
            ],
            dst_extra_clause='ON CONFLICT (stories_id) DO NOTHING',
        )

        self._move_generic_table_rows(
            src_table='topic_merged_stories_map',
            dst_table='topic_merged_stories_map',
            src_id_column='source_stories_id',
            # Really small table, can copy everything on one go; 3 chunks
            chunk_size=1_000_000_000,
            src_columns=[
                'source_stories_id',
                'target_stories_id',
            ],
            dst_columns=[
                'source_stories_id::BIGINT',
                'target_stories_id::BIGINT',
            ],
            dst_extra_clause='ON CONFLICT (source_stories_id, target_stories_id) DO NOTHING',
        )

        self._move_generic_table_rows_pkey(
            table='story_statistics',
            # Really small table, can copy everything on one go; 3 chunks
            chunk_size=1_000_000_000,
            src_columns_sans_pkey=[
                'stories_id',
                'facebook_share_count',
                'facebook_comment_count',
                'facebook_reaction_count',
                'facebook_api_collect_date',
                'facebook_api_error',
            ],
            dst_columns_sans_pkey=[
                'stories_id::BIGINT',
                'facebook_share_count::BIGINT',
                'facebook_comment_count::BIGINT',
                'facebook_reaction_count::BIGINT',
                'facebook_api_collect_date',
                'facebook_api_error',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='processed_stories',
            # 2,518,182,153 in source table; 51 chunks
            chunk_size=50_000_000,
            src_columns_sans_pkey=[
                'stories_id',
            ],
            dst_columns_sans_pkey=[
                'stories_id::BIGINT',
            ],
            dst_extra_clause='ON CONFLICT (stories_id) DO NOTHING',
        )

        self._move_generic_table_rows_pkey(
            table='scraped_stories',
            # Really small table, can copy everything on one go; 3 chunks
            chunk_size=1_000_000_000,
            src_columns_sans_pkey=[
                'stories_id',
                'import_module',
            ],
            dst_columns_sans_pkey=[
                'stories_id::BIGINT',
                'import_module',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='story_enclosures',
            # 153,858,997 in source table; 16 chunks
            chunk_size=10_000_000,
            src_columns_sans_pkey=[
                'stories_id',
                'url',
                'mime_type',
                'length',
            ],
            dst_columns_sans_pkey=[
                'stories_id::BIGINT',
                'url',
                'mime_type',
                'length',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='downloads',
            # 3,320,927,402 in source table; 67 chunks
            chunk_size=50_000_000,
            src_columns_sans_pkey=[
                'feeds_id',
                'stories_id',
                'parent',
                'url',
                'host',
                'download_time',
                'type',
                'state',
                'path',
                'error_message',
                'priority',
                'sequence',
                'extracted',
            ],
            dst_columns_sans_pkey=[
                'feeds_id::BIGINT',
                'stories_id::BIGINT',
                'parent',
                'url',
                'host',
                'download_time',
                'type::TEXT::public.download_type',
                'state::TEXT::public.download_state',
                'path',
                'error_message',
                'priority',
                'sequence',
                'extracted',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='download_texts',
            # 2,821,237,383 in source table; 57 chunks
            chunk_size=50_000_000,
            src_columns_sans_pkey=[
                'download_texts_id',
                'downloads_id',
                'download_text',
                'download_text_length',
            ],
            dst_columns_sans_pkey=[
                'download_texts_id',
                'downloads_id',
                'download_text',
                'download_text_length',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='topic_stories',
            # 165,026,730 in source table; 34 chunks
            chunk_size=5_000_000,
            src_columns_sans_pkey=[
                'topics_id',
                'stories_id',
                'link_mined',
                'iteration',
                'link_weight',
                'redirect_url',
                'valid_foreign_rss_story',
                'link_mine_error',
            ],
            dst_columns_sans_pkey=[
                'topics_id::BIGINT',
                'stories_id::BIGINT',
                'link_mined',
                'iteration::BIGINT',
                'link_weight',
                'redirect_url',
                'valid_foreign_rss_story',
                'link_mine_error',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='topic_links',
            # 1,433,314,412 in source table; 29 chunks
            chunk_size=50_000_000,
            src_columns_sans_pkey=[
                'topics_id',
                'stories_id',
                'url',
                'redirect_url',
                'ref_stories_id',
                'link_spidered',
            ],
            dst_columns_sans_pkey=[
                'topics_id::BIGINT',
                'stories_id::BIGINT',
                'url',
                'redirect_url',
                'ref_stories_id::BIGINT',
                'link_spidered',
            ],
        )

        self._move_generic_table_rows_pkey(
            table='topic_fetch_urls',
            # 705,821,290 in source table; 36 chunks
            chunk_size=20_000_000,
            src_columns_sans_pkey=[
                'topics_id',
                'url',
                'code',
                'fetch_date',
                'state',
                'message',
                'stories_id',
                'assume_match',
                'topic_links_id',
            ],
            dst_columns_sans_pkey=[
                'topics_id::BIGINT',
                'url',
                'code',
                'fetch_date',
                'state',
                'message',
                'stories_id::BIGINT',
                'assume_match',
                'topic_links_id::BIGINT',
            ],
        )

        # FIXME inner join
        self._move_generic_table_rows_pkey(
            table='topic_posts',
            # 95,486,494 in source table; 48 chunks
            chunk_size=2_000_000,
            src_columns_sans_pkey=[
                'topics_id',
                'topic_post_days_id',
                'data',
                'post_id',
                'content',
                'publish_date',
                'author',
                'channel',
                'url',
            ],
            dst_columns_sans_pkey=[
                'topics_id::BIGINT',
                'url',
                'code',
                'fetch_date',
                'state',
                'message',
                'stories_id::BIGINT',
                'assume_match',
                'topic_links_id::BIGINT',
            ],
        )
