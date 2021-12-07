from typing import List

# noinspection PyPackageRequirements
from temporal.workflow import Workflow

from mediawords.db import connect_to_db_or_raise
from mediawords.util.log import create_logger
from mediawords.workflow.exceptions import McProgrammingError

from .workflow_interface import MoveRowsToShardsWorkflow, MoveRowsToShardsActivities

log = create_logger(__name__)


# noinspection SqlResolve,SqlNoDataSourceInspection
class MoveRowsToShardsActivitiesImpl(MoveRowsToShardsActivities):
    """Activities implementation."""

    async def min_column_value(self, table: str, id_column: str) -> int:
        if '.' not in table:
            raise McProgrammingError(f"Table name must contain schema: {table}")
        if not table.startswith('unsharded_'):
            raise McProgrammingError(f"Table name must start with 'unsharded_': {table}")
        if '.' in id_column:
            raise McProgrammingError(f"Invalid ID column name: {id_column}")

        db = connect_to_db_or_raise()

        min_id = db.query(f"""
            SELECT MIN({id_column})
            FROM {table}
        """).flat()[0]

        if min_id is None:
            raise McProgrammingError(f"MIN({id_column}) is NULL for {table}")

        return min_id

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

        if max_id is None:
            raise McProgrammingError(f"MAX({id_column}) is NULL for {table}")

        return max_id

    async def move_chunk_of_rows(self,
                                 src_table: str,
                                 src_columns: List[str],
                                 src_id_column: str,
                                 src_id_start: int,
                                 src_id_end: int,
                                 src_extra_using_clause: str,
                                 src_extra_where_clause: str,
                                 dst_table: str,
                                 dst_columns: List[str],
                                 dst_extra_on_conflict_clause: str) -> None:
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

        insert_columns = ', '.join(src_columns)

        # Nasty hack: rename kinds like "feeds_stories_map_p_id" to "feeds_stories_map_id"
        insert_columns = insert_columns.replace('_p_', '_')

        sql = f"""
            WITH deleted_rows AS (
                DELETE FROM {src_table}
                {src_extra_using_clause}
                WHERE
                    {src_id_column} BETWEEN {src_id_start} AND {src_id_end}
                    {src_extra_where_clause}
                RETURNING {', '.join(src_columns)}
            )
            INSERT INTO {dst_table} ({insert_columns})
                SELECT {', '.join(dst_columns)}
                FROM deleted_rows
            {dst_extra_on_conflict_clause}
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

    async def _move_generic_table_rows(self,
                                       src_table: str,
                                       src_id_column: str,
                                       dst_table: str,
                                       chunk_size: int,
                                       src_columns: List[str],
                                       dst_columns: List[str],
                                       schema: str = 'public',
                                       src_extra_using_clause: str = '',
                                       src_extra_where_clause: str = '',
                                       dst_extra_on_conflict_clause: str = '') -> None:
        unsharded_table = f"unsharded_{schema}.{src_table}"
        sharded_table = f"sharded_{schema}.{dst_table}"

        min_id = await self.activities.min_column_value(unsharded_table, src_id_column)
        max_id = await self.activities.max_column_value(unsharded_table, src_id_column)

        for start_id in range(min_id, max_id + chunk_size, chunk_size):
            end_id = start_id + chunk_size
            await self.activities.move_chunk_of_rows(
                unsharded_table,
                src_columns,
                src_id_column,
                start_id,
                end_id,
                src_extra_using_clause,
                src_extra_where_clause,
                sharded_table,
                dst_columns,
                dst_extra_on_conflict_clause,
            )

        await self.activities.truncate_if_empty(unsharded_table)

    async def _move_generic_table_rows_pkey(self,
                                            table: str,
                                            chunk_size: int,
                                            src_columns_sans_pkey: List[str],
                                            dst_columns_sans_pkey: List[str],
                                            schema: str = 'public',
                                            dst_extra_on_conflict_clause: str = '') -> None:
        # Same ID column name on both source and destination tables
        id_column = f"{table}_id"

        await self._move_generic_table_rows(
            src_table=table,
            dst_table=table,
            src_id_column=id_column,
            chunk_size=chunk_size,
            src_columns=[id_column] + src_columns_sans_pkey,
            dst_columns=[f'{id_column}::BIGINT'] + dst_columns_sans_pkey,
            schema=schema,
            dst_extra_on_conflict_clause=dst_extra_on_conflict_clause,
        )

    async def move_rows_to_shards(self) -> None:
        await self._move_generic_table_rows_pkey(
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
            dst_extra_on_conflict_clause='ON CONFLICT (email, day) DO NOTHING',
        )

        await self._move_generic_table_rows_pkey(
            table='media_stats',
            # 89,970,140 in source table; 9 chunks
            chunk_size=10_000_000,
            src_columns_sans_pkey=[
                'media_id',
                'num_stories',
                'num_sentences',
                'stat_date',
            ],
            dst_columns_sans_pkey=[
                'media_id::BIGINT',
                'num_stories::BIGINT',
                'num_sentences::BIGINT',
                'stat_date',
            ],
            dst_extra_on_conflict_clause='ON CONFLICT (media_id, stat_date) DO NOTHING',
        )

        await self._move_generic_table_rows(
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

        await self._move_generic_table_rows_pkey(
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

        await self._move_generic_table_rows_pkey(
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

        await self._move_generic_table_rows_pkey(
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

        max_stories_id = await self.activities.max_column_value('unsharded_public.feeds_stories_map', 'stories_id')
        stories_id_chunk_size = 100_000_000

        for partition_index in range(int(max_stories_id / stories_id_chunk_size) + 1):
            await self._move_generic_table_rows(
                src_table=f'feeds_stories_map_p_{str(partition_index).zfill(2)}',
                dst_table='feeds_stories_map',
                src_id_column='stories_id',
                # 96,563,848 in source table; 10 chunks
                chunk_size=10_000_000,
                src_columns=[
                    'feeds_stories_map_p_id',
                    'feeds_id',
                    'stories_id',
                ],
                dst_columns=[
                    'feeds_stories_map_p_id::BIGINT AS feeds_stories_map_id',
                    'feeds_id::BIGINT',
                    'stories_id::BIGINT',
                ],
            )

        for partition_index in range(int(max_stories_id / stories_id_chunk_size) + 1):
            await self._move_generic_table_rows(
                src_table=f'stories_tags_map_p_{str(partition_index).zfill(2)}',
                dst_table='stories_tags_map',
                src_id_column='stories_id',
                # 547,023,872 in every partition; 28 chunks
                chunk_size=20_000_000,
                src_columns=[
                    'stories_tags_map_p_id',
                    'stories_id',
                    'tags_id',
                ],
                dst_columns=[
                    'stories_tags_map_p_id::BIGINT AS stories_tags_map_id',
                    'stories_id::BIGINT',
                    'tags_id::BIGINT',
                ],
            )

        for partition_index in range(int(max_stories_id / stories_id_chunk_size) + 1):
            await self._move_generic_table_rows(
                src_table=f'story_sentences_p_{str(partition_index).zfill(2)}',
                dst_table='story_sentences',
                src_id_column='stories_id',
                # 1,418,730,496 in every partition; 29 chunks
                chunk_size=50_000_000,
                src_columns=[
                    'story_sentences_p_id',
                    'stories_id',
                    'sentence_number',
                    'sentence',
                    'media_id',
                    'publish_date',
                    'language',
                    'is_dup',
                ],
                dst_columns=[
                    'story_sentences_p_id::BIGINT AS story_sentences_id',
                    'stories_id::BIGINT',
                    'sentence_number',
                    'sentence',
                    'media_id::BIGINT',
                    'publish_date',
                    'language',
                    'is_dup',
                ],
            )

        await self._move_generic_table_rows(
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
            dst_extra_on_conflict_clause='ON CONFLICT (stories_id) DO NOTHING',
        )

        await self._move_generic_table_rows(
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
            dst_extra_on_conflict_clause='ON CONFLICT (stories_id) DO NOTHING',
        )

        await self._move_generic_table_rows(
            src_table='topic_merged_stories_map',
            dst_table='topic_merged_stories_map',
            src_id_column='source_stories_id',
            # Rather small table, can copy everything on one go; 3 chunks
            chunk_size=1_000_000_000,
            src_columns=[
                'source_stories_id',
                'target_stories_id',
            ],
            dst_columns=[
                'source_stories_id::BIGINT',
                'target_stories_id::BIGINT',
            ],
            dst_extra_on_conflict_clause='ON CONFLICT (source_stories_id, target_stories_id) DO NOTHING',
        )

        await self._move_generic_table_rows_pkey(
            table='story_statistics',
            # Rather small table, can copy everything on one go; 3 chunks
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

        # FIXME fails with
        #
        # 2021-12-07 13:39:30 EST [64-1] mediacloud@mediacloud ERROR:  cannot use 2PC in transactions involving multiple servers
        # 2021-12-07 13:39:30 EST [64-2] mediacloud@mediacloud STATEMENT:  PREPARE TRANSACTION 'citus_0_63_89_0'
        # 2021-12-07 13:39:30 EST [63-1] mediacloud@mediacloud ERROR:  cannot use 2PC in transactions involving multiple servers
        # 2021-12-07 13:39:30 EST [63-2] mediacloud@mediacloud CONTEXT:  while executing command on localhost:5432
        # 2021-12-07 13:39:30 EST [63-3] mediacloud@mediacloud STATEMENT:
        # 	            WITH deleted_rows AS (
        # 	                DELETE FROM unsharded_public.processed_stories
        #
        # 	                WHERE
        # 	                    processed_stories_id BETWEEN 1 AND 50000001
        #
        # 	                RETURNING processed_stories_id, stories_id
        # 	            )
        # 	            INSERT INTO sharded_public.processed_stories (processed_stories_id, stories_id)
        # 	                SELECT processed_stories_id::BIGINT, stories_id::BIGINT
        # 	                FROM deleted_rows
        # 	            ON CONFLICT (stories_id) DO NOTHING
        await self._move_generic_table_rows_pkey(
            table='processed_stories',
            # 2,518,182,153 in source table; 51 chunks
            chunk_size=50_000_000,
            src_columns_sans_pkey=[
                'stories_id',
            ],
            dst_columns_sans_pkey=[
                'stories_id::BIGINT',
            ],
            dst_extra_on_conflict_clause='ON CONFLICT (stories_id) DO NOTHING',
        )

        await self._move_generic_table_rows_pkey(
            table='scraped_stories',
            # Rather small table, can copy everything on one go; 3 chunks
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

        await self._move_generic_table_rows_pkey(
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

        downloads_id_src_columns = [
            'downloads_id',
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
        ]
        downloads_id_dst_columns = [
            'downloads_id::BIGINT',
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
        ]

        max_downloads_id = await self.activities.max_column_value('unsharded_public.downloads', 'downloads_id')
        downloads_id_chunk_size = stories_id_chunk_size

        # FIXME fails with:
        #
        # 2021-12-07 13:41:07 EST [91-1] mediacloud@mediacloud ERROR:  relation "sharded_public.downloads_error" does not exist at character 412
        # 2021-12-07 13:41:07 EST [91-2] mediacloud@mediacloud STATEMENT:
        # 	            WITH deleted_rows AS (
        # 	                DELETE FROM unsharded_public.downloads_error
        #
        # 	                WHERE
        # 	                    downloads_id BETWEEN 1 AND 10000001
        #
        # 	                RETURNING downloads_id, feeds_id, stories_id, parent, url, host, download_time, type, state, path, error_message, priority, sequence, extracted
        # 	            )
        # 	            INSERT INTO sharded_public.downloads_error (downloads_id, feeds_id, stories_id, parent, url, host, download_time, type, state, path, error_message, priority, sequence, extracted)
        # 	                SELECT downloads_id::BIGINT, feeds_id::BIGINT, stories_id::BIGINT, parent, url, host, download_time, type::TEXT::public.download_type, state::TEXT::public.download_state, path, error_message, priority, sequence, extracted
        # 	                FROM deleted_rows
        await self._move_generic_table_rows(
            src_table='downloads_error',
            dst_table=f'downloads_error',
            src_id_column='downloads_id',
            # 114,330,304 in source table; 12 chunks
            chunk_size=10_000_000,
            src_columns=downloads_id_src_columns,
            dst_columns=downloads_id_dst_columns,
        )

        for partition_index in range(int(max_downloads_id / downloads_id_chunk_size) + 1):
            await self._move_generic_table_rows(
                src_table=f'downloads_success_content_{str(partition_index).zfill(2)}',
                dst_table=f'downloads_success',
                src_id_column='downloads_id',
                # 65,003,792 in source table; 7 chunks
                chunk_size=10_000_000,
                src_columns=downloads_id_src_columns,
                dst_columns=downloads_id_dst_columns,
            )

        for partition_index in range(int(max_downloads_id / downloads_id_chunk_size) + 1):
            await self._move_generic_table_rows(
                src_table=f'downloads_success_feed_{str(partition_index).zfill(2)}',
                dst_table=f'downloads_success',
                src_id_column='downloads_id',
                # 45,088,116 in source table; 5 chunks
                chunk_size=10_000_000,
                src_columns=downloads_id_src_columns,
                dst_columns=downloads_id_dst_columns,
            )

        for partition_index in range(int(max_downloads_id / downloads_id_chunk_size) + 1):
            await self._move_generic_table_rows(
                src_table=f'download_texts_{str(partition_index).zfill(2)}',
                dst_table=f'download_texts',
                src_id_column='downloads_id',
                # 69,438,480 in source table; 7 chunks
                chunk_size=10_000_000,
                src_columns=[
                    'download_texts_id',
                    'downloads_id',
                    'download_text',
                    'download_text_length',
                ],
                dst_columns=[
                    'download_texts_id',
                    'downloads_id',
                    'download_text',
                    'download_text_length',
                ],
            )

        await self._move_generic_table_rows_pkey(
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

        await self._move_generic_table_rows_pkey(
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

        await self._move_generic_table_rows_pkey(
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

        await self._move_generic_table_rows(
            src_table='topic_posts',
            dst_table='topic_posts',
            src_id_column='topic_posts_id',
            # 95,486,494 in source table; 48 chunks
            chunk_size=2_000_000,
            src_columns=[
                'unsharded_public.topic_posts.topic_posts_id',
                'public.topic_post_days.topics_id',
                'unsharded_public.topic_posts.topic_post_days_id',
                'unsharded_public.topic_posts.data',
                'unsharded_public.topic_posts.post_id',
                'unsharded_public.topic_posts.content',
                'unsharded_public.topic_posts.publish_date',
                'unsharded_public.topic_posts.author',
                'unsharded_public.topic_posts.channel',
                'unsharded_public.topic_posts.url',
            ],
            dst_columns=[
                'topic_posts_id::BIGINT',
                'topics_id',
                'topic_post_days_id::BIGINT',
                'data',
                'post_id::TEXT',
                'content',
                'publish_date',
                'author::TEXT',
                'channel::TEXT',
                'url',
            ],
            src_extra_using_clause='USING public.topic_post_days',
            src_extra_where_clause="""
                AND unsharded_public.topic_posts.topic_post_days_id = public.topic_post_days.topic_post_days_id
            """,
        )

        # FIXME depends on topic_posts being moved first
        await self._move_generic_table_rows(
            src_table='topic_post_urls',
            dst_table='topic_post_urls',
            src_id_column='topic_post_urls_id',
            # 50,726,436 in source table; 25 chunks
            chunk_size=2_000_000,
            src_columns=[
                'public.topic_post_days.topics_id',
                'unsharded_public.topic_post_urls.topic_posts_id',
                'unsharded_public.topic_post_urls.url',
            ],
            dst_columns=[
                'topic_post_days.topics_id',
                'topic_post_urls.topic_posts_id::BIGINT',
                'topic_post_urls.url::TEXT',
            ],
            src_extra_using_clause='USING sharded_public.topic_posts, public.topic_post_days',
            src_extra_where_clause="""
                AND unsharded_public.topic_post_urls.topic_posts_id = sharded_public.topic_posts.topic_posts_id
                AND sharded_public.topic_posts.topic_post_days_id = public.topic_post_days.topic_post_days_id
            """,
        )

        await self._move_generic_table_rows_pkey(
            table='topic_seed_urls',
            # 499,926,808 in source table; 50 chunks
            chunk_size=10_000_000,
            src_columns_sans_pkey=[
                'topics_id',
                'url',
                'source',
                'stories_id',
                'processed',
                'assume_match',
                'content',
                'guid',
                'title',
                'publish_date',
                'topic_seed_queries_id',
                'topic_post_urls_id',
            ],
            dst_columns_sans_pkey=[
                'topics_id::BIGINT',
                'url',
                'source',
                'stories_id::BIGINT',
                'processed',
                'assume_match',
                'content',
                'guid',
                'title',
                'publish_date',
                'topic_seed_queries_id::BIGINT',
                'topic_post_urls_id::BIGINT',
            ],
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='stories',
            dst_table='stories',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            src_columns=[
                'public.snapshots.topics_id',
                'unsharded_snap.stories.snapshots_id',
                'unsharded_snap.stories.stories_id',
                'unsharded_snap.stories.media_id',
                'unsharded_snap.stories.url',
                'unsharded_snap.stories.guid',
                'unsharded_snap.stories.title',
                'unsharded_snap.stories.publish_date',
                'unsharded_snap.stories.collect_date',
                'unsharded_snap.stories.full_text_rss',
                'unsharded_snap.stories.language',
            ],
            dst_columns=[
                'topics_id',
                'snapshots_id::BIGINT',
                'stories_id::BIGINT',
                'media_id::BIGINT',
                'url::TEXT',
                'guid::TEXT',
                'title',
                'publish_date',
                'collect_date',
                'full_text_rss',
                'language',
            ],
            src_extra_using_clause='USING public.snapshots',
            src_extra_where_clause="AND unsharded_snap.stories.snapshots_id = public.snapshots.snapshots_id",
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, snapshots_id, stories_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='topic_stories',
            dst_table='topic_stories',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            src_columns=[
                'topics_id',
                'snapshots_id',
                'topic_stories_id',
                'stories_id',
                'link_mined',
                'iteration',
                'link_weight',
                'redirect_url',
                'valid_foreign_rss_story',
            ],
            dst_columns=[
                'topics_id::BIGINT',
                'snapshots_id::BIGINT',
                'topic_stories_id::BIGINT',
                'stories_id::BIGINT',
                'link_mined',
                'iteration::BIGINT',
                'link_weight',
                'redirect_url',
                'valid_foreign_rss_story',
            ],
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, snapshots_id, stories_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='topic_links_cross_media',
            dst_table='topic_links_cross_media',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            src_columns=[
                'topics_id',
                'snapshots_id',
                'topic_links_id',
                'stories_id',
                'url',
                'ref_stories_id',
            ],
            dst_columns=[
                'topics_id::BIGINT',
                'snapshots_id::BIGINT',
                'topic_links_id::BIGINT',
                'stories_id::BIGINT',
                'url',
                'ref_stories_id::BIGINT',
            ],
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, snapshots_id, stories_id, ref_stories_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='media',
            dst_table='media',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            src_columns=[
                'public.snapshots.topics_id',
                'unsharded_snap.media.snapshots_id',
                'unsharded_snap.media.media_id',
                'unsharded_snap.media.url',
                'unsharded_snap.media.name',
                'unsharded_snap.media.full_text_rss',
                'unsharded_snap.media.foreign_rss_links',
                'unsharded_snap.media.dup_media_id',
                'unsharded_snap.media.is_not_dup',
            ],
            dst_columns=[
                'topics_id',
                'snapshots_id::BIGINT',
                'media_id::BIGINT',
                'url::TEXT',
                'name::TEXT',
                'full_text_rss',
                'foreign_rss_links',
                'dup_media_id::BIGINT',
                'is_not_dup',
            ],
            src_extra_using_clause='USING public.snapshots',
            src_extra_where_clause="AND unsharded_snap.media.snapshots_id = public.snapshots.snapshots_id",
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, snapshots_id, media_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='media_tags_map',
            dst_table='media_tags_map',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            src_columns=[
                'public.snapshots.topics_id',
                'unsharded_snap.snap_media_tags_map.snapshots_id',
                'unsharded_snap.snap_media_tags_map.media_tags_map_id',
                'unsharded_snap.snap_media_tags_map.media_id',
                'unsharded_snap.snap_media_tags_map.tags_id',
            ],
            dst_columns=[
                'topics_id',
                'snapshots_id::BIGINT',
                'media_tags_map_id::BIGINT',
                'media_id::BIGINT',
                'tags_id::BIGINT',
            ],
            src_extra_using_clause='USING public.snapshots',
            src_extra_where_clause="""
                AND unsharded_snap.snap_media_tags_map.snapshots_id = public.snapshots.snapshots_id
            """,
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, snapshots_id, media_id, tags_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='stories_tags_map',
            dst_table='stories_tags_map',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            src_columns=[
                'public.snapshots.topics_id',
                'unsharded_snap.snap_media_tags_map.snapshots_id',
                'unsharded_snap.snap_media_tags_map.stories_tags_map_id',
                'unsharded_snap.snap_media_tags_map.stories_id',
                'unsharded_snap.snap_media_tags_map.tags_id',
            ],
            dst_columns=[
                'topics_id',
                'snapshots_id::BIGINT',
                'stories_tags_map_id::BIGINT',
                'stories_id::BIGINT',
                'tags_id::BIGINT',
            ],
            src_extra_using_clause='USING public.snapshots',
            src_extra_where_clause="""
                AND unsharded_snap.stories_tags_map.snapshots_id = public.snapshots.snapshots_id
            """,
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, snapshots_id, stories_id, tags_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='story_links',
            dst_table='story_links',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            src_columns=[
                'public.timespans.topics_id',
                'unsharded_snap.story_links.timespans_id',
                'unsharded_snap.story_links.source_stories_id',
                'unsharded_snap.story_links.ref_stories_id',
            ],
            dst_columns=[
                'topics_id',
                'timespans_id::BIGINT',
                'source_stories_id::BIGINT',
                'ref_stories_id::BIGINT',
            ],
            src_extra_using_clause='USING public.timespans',
            src_extra_where_clause="""
                AND unsharded_snap.story_links.timespans_id = public.timespans.timespans_id
            """,
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, timespans_id, source_stories_id, ref_stories_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='story_link_counts',
            dst_table='story_link_counts',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            src_columns=[
                'public.timespans.topics_id',
                'unsharded_snap.story_link_counts.timespans_id',
                'unsharded_snap.story_link_counts.stories_id',
                'unsharded_snap.story_link_counts.media_inlink_count',
                'unsharded_snap.story_link_counts.inlink_count',
                'unsharded_snap.story_link_counts.outlink_count',
                'unsharded_snap.story_link_counts.facebook_share_count',
                'unsharded_snap.story_link_counts.post_count',
                'unsharded_snap.story_link_counts.author_count',
                'unsharded_snap.story_link_counts.channel_count',
            ],
            dst_columns=[
                'topics_id',
                'timespans_id::BIGINT',
                'stories_id::BIGINT',
                'media_inlink_count::BIGINT',
                'inlink_count::BIGINT',
                'outlink_count::BIGINT',
                'facebook_share_count::BIGINT',
                'post_count::BIGINT',
                'author_count::BIGINT',
                'channel_count::BIGINT',
            ],
            src_extra_using_clause='USING public.timespans',
            src_extra_where_clause="""
                AND unsharded_snap.story_link_counts.timespans_id = public.timespans.timespans_id
            """,
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, timespans_id, stories_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='medium_link_counts',
            dst_table='medium_link_counts',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            src_columns=[
                'public.timespans.topics_id',
                'unsharded_snap.medium_link_counts.timespans_id',
                'unsharded_snap.medium_link_counts.media_id',
                'unsharded_snap.medium_link_counts.sum_media_inlink_count',
                'unsharded_snap.medium_link_counts.media_inlink_count',
                'unsharded_snap.medium_link_counts.inlink_count',
                'unsharded_snap.medium_link_counts.outlink_count',
                'unsharded_snap.medium_link_counts.story_count',
                'unsharded_snap.medium_link_counts.facebook_share_count',
                'unsharded_snap.medium_link_counts.sum_post_count',
                'unsharded_snap.medium_link_counts.sum_author_count',
                'unsharded_snap.medium_link_counts.sum_channel_count',
            ],
            dst_columns=[
                'topics_id',
                'timespans_id::BIGINT',
                'media_id::BIGINT',
                'sum_media_inlink_count::BIGINT',
                'media_inlink_count::BIGINT',
                'inlink_count::BIGINT',
                'outlink_count::BIGINT',
                'story_count::BIGINT',
                'facebook_share_count::BIGINT',
                'sum_post_count::BIGINT',
                'sum_author_count::BIGINT',
                'sum_channel_count::BIGINT',
            ],
            src_extra_using_clause='USING public.timespans',
            src_extra_where_clause="""
                AND unsharded_snap.medium_link_counts.timespans_id = public.timespans.timespans_id
            """,
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, timespans_id, media_id) DO NOTHING
            """,
        )

        await self._move_generic_table_rows(
            schema='snap',
            src_table='medium_links',
            dst_table='medium_links',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            src_columns=[
                'public.timespans.topics_id',
                'unsharded_snap.medium_links.timespans_id',
                'unsharded_snap.medium_links.source_media_id',
                'unsharded_snap.medium_links.ref_media_id',
                'unsharded_snap.medium_links.link_count',
            ],
            dst_columns=[
                'topics_id',
                'timespans_id::BIGINT',
                'source_media_id::BIGINT',
                'ref_media_id::BIGINT',
                'link_count::BIGINT',
            ],
            src_extra_using_clause='USING public.timespans',
            src_extra_where_clause="AND unsharded_snap.medium_links.timespans_id = public.timespans.timespans_id",
            dst_extra_on_conflict_clause="""
                ON CONFLICT (topics_id, timespans_id, source_media_id, ref_media_id) DO NOTHING
            """,
        )

        # FIXME have to copy topic_posts first
        await self._move_generic_table_rows(
            schema='snap',
            src_table='timespan_posts',
            dst_table='timespan_posts',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 95_486_498 in source table; 20 chunks
            chunk_size=5_000_000,
            src_columns=[
                'public.timespans.topics_id',
                'unsharded_snap.timespan_posts.timespans_id',
                'unsharded_snap.timespan_posts.topic_posts_id',
            ],
            dst_columns=[
                'topics_id',
                'timespans_id::BIGINT',
                'topic_posts_id::BIGINT',
            ],
            src_extra_using_clause='USING public.timespans',
            src_extra_where_clause="AND unsharded_snap.timespan_posts.timespans_id = public.timespans.timespans_id",
        )

        # FIXME have to copy topic_stories first
        await self._move_generic_table_rows(
            schema='snap',
            src_table='live_stories',
            dst_table='live_stories',
            src_id_column='topic_stories_id',
            # MAX(topic_stories_id) = 165_082_931 in source table; 34 chunks
            chunk_size=5_000_000,
            src_columns=[
                'topics_id',
                'topic_stories_id',
                'stories_id',
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
            dst_columns=[
                'topics_id::BIGINT',
                'topic_stories_id::BIGINT',
                'stories_id::BIGINT',
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
