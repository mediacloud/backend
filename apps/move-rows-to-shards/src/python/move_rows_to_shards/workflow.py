import re
from typing import List, Optional

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

    async def min_column_value(self, table: str, id_column: str) -> Optional[int]:
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

        return min_id

    async def max_column_value(self, table: str, id_column: str) -> Optional[int]:
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

    async def run_queries_in_transaction(self, sql_queries: List[str]) -> None:

        db = connect_to_db_or_raise()

        log.info(f"Executing queries: {sql_queries}")

        if len(sql_queries) > 1:
            db.begin()

        for query in sql_queries:
            db.query(query)

        if len(sql_queries) > 1:
            db.commit()

        log.info(f"Executed queries: {sql_queries}")

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

    __START_ID_MARKER = '**START_ID**'
    __END_ID_MARKER = '**END_ID**'

    def __init__(self):
        self.activities: MoveRowsToShardsActivities = Workflow.new_activity_stub(
            activities_cls=MoveRowsToShardsActivities,
            # No retry_parameters here as they get set individually in @activity_method()
        )

    # Helper, not a workflow method
    async def _move_table(self, src_table: str, src_id_column: str, chunk_size: int, sql_queries: List[str]):
        if '.' not in src_table:
            raise McProgrammingError(f"Source table name must contain schema: {src_table}")
        if not src_table.startswith('unsharded_'):
            raise McProgrammingError(f"Source table name must start with 'unsharded_': {src_table}")
        if '.' in src_id_column:
            raise McProgrammingError(f"Invalid source ID column name: {src_id_column}")

        start_id_marker_found = end_id_marker_found = False

        for query in sql_queries:
            if self.__START_ID_MARKER in query:
                start_id_marker_found = True
            if self.__END_ID_MARKER in query:
                end_id_marker_found = True

        if not start_id_marker_found:
            raise McProgrammingError(
                f"SQL queries don't contain start ID marker '{self.__START_ID_MARKER}': {sql_queries}"
            )
        if not end_id_marker_found:
            raise McProgrammingError(
                f"SQL queries don't contain end ID marker '{self.__END_ID_MARKER}': {sql_queries}"
            )

        min_id = await self.activities.min_column_value(src_table, src_id_column)
        if min_id is None:
            log.warning(f"Table {src_table} seems to be empty.")
            return

        max_id = await self.activities.max_column_value(src_table, src_id_column)
        if max_id is None:
            log.warning(f"Table {src_table} seems to be empty.")
            return

        for start_id in range(min_id, max_id + chunk_size, chunk_size):
            end_id = start_id + chunk_size

            sql_queries_with_ids = []

            for query in sql_queries:
                query = query.replace(self.__START_ID_MARKER, str(start_id))
                query = query.replace(self.__END_ID_MARKER, str(end_id))

                # Make queries look nicer in Temporal's log
                query = re.sub(r'\s+', ' ', query)
                query = query.strip()

                sql_queries_with_ids.append(query)

            await self.activities.run_queries_in_transaction(sql_queries_with_ids)

        await self.activities.truncate_if_empty(src_table)

    # noinspection SqlResolve,SqlNoDataSourceInspection
    async def move_rows_to_shards(self) -> None:

        await self._move_table(
            src_table='unsharded_public.auth_user_request_daily_counts',
            src_id_column='auth_user_request_daily_counts_id',
            # 338,454,970 rows in source table; 17 chunks
            chunk_size=20_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.auth_user_request_daily_counts
                        WHERE auth_user_request_daily_counts_id BETWEEN {self.__START_ID_MARKER}
                                                                AND     {self.__END_ID_MARKER}
                        RETURNING
                            auth_user_request_daily_counts_id,
                            email,
                            day,
                            requests_count,
                            requested_items_count
                    )
                    INSERT INTO sharded_public.auth_user_request_daily_counts (
                        auth_user_request_daily_counts_id,
                        email,
                        day,
                        requests_count,
                        requested_items_count
                    )
                        SELECT
                            auth_user_request_daily_counts_id::BIGINT,
                            email,
                            day,
                            requests_count::BIGINT,
                            requested_items_count::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (email, day) DO NOTHING
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.media_stats',
            src_id_column='media_stats_id',
            # 89,970,140 in source table; 9 chunks
            chunk_size=10_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.media_stats
                        WHERE media_stats_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            media_stats_id,
                            media_id,
                            num_stories,
                            num_sentences,
                            stat_date
                    )
                    INSERT INTO sharded_public.media_stats (
                        media_stats_id,
                        media_id,
                        num_stories,
                        num_sentences,
                        stat_date
                    )
                        SELECT
                            media_stats_id::BIGINT,
                            media_id::BIGINT,
                            num_stories::BIGINT,
                            num_sentences::BIGINT,
                            stat_date
                        FROM deleted_rows
                    ON CONFLICT (media_id, stat_date) DO NOTHING
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.media_coverage_gaps',
            src_id_column='media_id',
            # MAX(media_id) = 1,892,933; 63,132,122 rows in source table; 19 chunks
            chunk_size=100_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.media_coverage_gaps
                        WHERE media_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            media_id,
                            stat_week,
                            num_stories,
                            expected_stories,
                            num_sentences,
                            expected_sentences
                    )
                    INSERT INTO sharded_public.media_coverage_gaps (
                        media_id,
                        stat_week,
                        num_stories,
                        expected_stories,
                        num_sentences,
                        expected_sentences
                    )
                        SELECT
                            media_id::BIGINT,
                            stat_week,
                            num_stories,
                            expected_stories,
                            num_sentences,
                            expected_sentences
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.stories',
            src_id_column='stories_id',
            # 2,119,319,121 in source table; 43 chunks
            chunk_size=50_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.stories
                        WHERE stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            stories_id,
                            media_id,
                            url,
                            guid,
                            title,
                            normalized_title_hash,
                            description,
                            publish_date,
                            collect_date,
                            full_text_rss,
                            language
                    )
                    INSERT INTO sharded_public.stories (
                        stories_id,
                        media_id,
                        url,
                        guid,
                        title,
                        normalized_title_hash,
                        description,
                        publish_date,
                        collect_date,
                        full_text_rss,
                        language
                    )
                        SELECT
                            stories_id::BIGINT,
                            media_id::BIGINT,
                            url::TEXT,
                            guid::TEXT,
                            title,
                            normalized_title_hash,
                            description,
                            publish_date,
                            collect_date,
                            full_text_rss,
                            language
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.stories_ap_syndicated',
            src_id_column='stories_ap_syndicated_id',
            # 1,715,725,719 in source table; 35 chunks
            chunk_size=50_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.stories_ap_syndicated
                        WHERE stories_ap_syndicated_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            stories_ap_syndicated_id,
                            stories_id,
                            ap_syndicated
                    )
                    INSERT INTO sharded_public.stories_ap_syndicated (
                        stories_ap_syndicated_id,
                        stories_id,
                        ap_syndicated
                    )
                        SELECT
                            stories_ap_syndicated_id::BIGINT,
                            stories_id::BIGINT,
                            ap_syndicated
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.story_urls',
            src_id_column='story_urls_id',
            # 2,223,082,697 in source table; 45 chunks
            chunk_size=50_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.story_urls
                        WHERE story_urls_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            story_urls_id,
                            stories_id,
                            url
                    )
                    INSERT INTO sharded_public.story_urls (
                        story_urls_id,
                        stories_id,
                        url
                    )
                        SELECT
                            story_urls_id::BIGINT,
                            stories_id::BIGINT,
                            url::TEXT
                        FROM deleted_rows
                """
            ],
        )

        max_stories_id = await self.activities.max_column_value('unsharded_public.feeds_stories_map', 'stories_id')
        stories_id_chunk_size = 100_000_000

        for partition_index in range(int(max_stories_id / stories_id_chunk_size) + 1):
            await self._move_table(
                src_table=f'unsharded_public.feeds_stories_map_p_{str(partition_index).zfill(2)}',
                src_id_column='stories_id',
                # 96,563,848 in source table; 10 chunks
                chunk_size=10_000_000,
                sql_queries=[
                    f"""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.feeds_stories_map_p_{str(partition_index).zfill(2)}
                            WHERE stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                            RETURNING
                                feeds_stories_map_p_id,
                                feeds_id,
                                stories_id
                        )
                        INSERT INTO sharded_public.feeds_stories_map (
                            feeds_stories_map_id,
                            feeds_id,
                            stories_id
                        )
                            SELECT
                                feeds_stories_map_p_id::BIGINT AS feeds_stories_map_id,
                                feeds_id::BIGINT,
                                stories_id::BIGINT
                            FROM deleted_rows
                    """
                ],
            )

        for partition_index in range(int(max_stories_id / stories_id_chunk_size) + 1):
            await self._move_table(
                src_table=f'unsharded_public.stories_tags_map_p_{str(partition_index).zfill(2)}',
                src_id_column='stories_id',
                # 547,023,872 in every partition; 28 chunks
                chunk_size=20_000_000,
                sql_queries=[
                    f"""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.stories_tags_map_p_{str(partition_index).zfill(2)}
                            WHERE stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                            RETURNING
                                stories_tags_map_p_id,
                                stories_id,
                                tags_id
                        )
                        INSERT INTO sharded_public.stories_tags_map (
                            stories_tags_map_id,
                            stories_id,
                            tags_id
                        )
                            SELECT
                                stories_tags_map_p_id::BIGINT AS stories_tags_map_id,
                                stories_id::BIGINT,
                                tags_id::BIGINT
                            FROM deleted_rows
                    """
                ],
            )

        for partition_index in range(int(max_stories_id / stories_id_chunk_size) + 1):
            await self._move_table(
                src_table=f'unsharded_public.story_sentences_p_{str(partition_index).zfill(2)}',
                src_id_column='stories_id',
                # 1,418,730,496 in every partition; 29 chunks
                chunk_size=50_000_000,
                sql_queries=[
                    f"""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.story_sentences_p_{str(partition_index).zfill(2)}
                            WHERE stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                            RETURNING
                                story_sentences_p_id,
                                stories_id,
                                sentence_number,
                                sentence,
                                media_id,
                                publish_date,
                                language,
                                is_dup
                        )
                        INSERT INTO sharded_public.story_sentences (
                            story_sentences_id,
                            stories_id,
                            sentence_number,
                            sentence,
                            media_id,
                            publish_date,
                            language,
                            is_dup
                        )
                            SELECT
                                story_sentences_p_id::BIGINT AS story_sentences_id,
                                stories_id::BIGINT,
                                sentence_number,
                                sentence,
                                media_id::BIGINT,
                                publish_date,
                                language,
                                is_dup
                            FROM deleted_rows
                    """
                ],
            )

        await self._move_table(
            src_table=f'unsharded_public.solr_import_stories',
            src_id_column='stories_id',
            # Rather small table, can copy everything in one go; 3 chunks
            chunk_size=1_000_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.solr_import_stories
                        WHERE stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING stories_id
                    )
                    INSERT INTO sharded_public.solr_import_stories (stories_id)
                        SELECT stories_id::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (stories_id) DO NOTHING
                """
            ],
        )

        await self._move_table(
            src_table=f'unsharded_public.solr_imported_stories',
            src_id_column='stories_id',
            # MAX(stories_id) = 2,119,343,981; 43 chunks
            chunk_size=50_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.solr_imported_stories
                        WHERE stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            stories_id,
                            import_date
                    )
                    INSERT INTO sharded_public.solr_imported_stories (
                        stories_id,
                        import_date
                    )
                        SELECT
                            stories_id::BIGINT,
                            import_date
                        FROM deleted_rows
                    ON CONFLICT (stories_id) DO NOTHING
                """
            ],
        )

        await self._move_table(
            src_table=f'unsharded_public.topic_merged_stories_map',
            src_id_column='source_stories_id',
            # Rather small table, can copy everything on one go; 3 chunks
            chunk_size=1_000_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.topic_merged_stories_map
                        WHERE source_stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            source_stories_id,
                            target_stories_id
                    )
                    INSERT INTO sharded_public.topic_merged_stories_map (
                        source_stories_id,
                        target_stories_id
                    )
                        SELECT
                            source_stories_id::BIGINT,
                            target_stories_id::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (source_stories_id, target_stories_id) DO NOTHING
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.story_statistics',
            src_id_column='story_statistics_id',
            # Rather small table, can copy everything on one go; 3 chunks
            chunk_size=1_000_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.story_statistics
                        WHERE story_statistics_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            story_statistics_id,
                            stories_id,
                            facebook_share_count,
                            facebook_comment_count,
                            facebook_reaction_count,
                            facebook_api_collect_date,
                            facebook_api_error
                    )
                    INSERT INTO sharded_public.story_statistics (
                        story_statistics_id,
                        stories_id,
                        facebook_share_count,
                        facebook_comment_count,
                        facebook_reaction_count,
                        facebook_api_collect_date,
                        facebook_api_error
                    )
                        SELECT
                            story_statistics_id::BIGINT,
                            stories_id::BIGINT,
                            facebook_share_count::BIGINT,
                            facebook_comment_count::BIGINT,
                            facebook_reaction_count::BIGINT,
                            facebook_api_collect_date,
                            facebook_api_error
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.processed_stories',
            src_id_column='processed_stories_id',
            # 2,518,182,153 in source table; 51 chunks
            chunk_size=50_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.processed_stories
                        WHERE processed_stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            processed_stories_id,
                            stories_id
                    )
                    INSERT INTO sharded_public.processed_stories (
                        processed_stories_id,
                        stories_id
                    )
                        SELECT
                            processed_stories_id::BIGINT,
                            stories_id::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (stories_id) DO NOTHING
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.scraped_stories',
            src_id_column='scraped_stories_id',
            # Rather small table, can copy everything on one go; 3 chunks
            chunk_size=1_000_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.scraped_stories
                        WHERE scraped_stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            scraped_stories_id,
                            stories_id,
                            import_module
                    )
                    INSERT INTO sharded_public.scraped_stories (
                        scraped_stories_id,
                        stories_id,
                        import_module
                    )
                        SELECT
                            scraped_stories_id::BIGINT,
                            stories_id::BIGINT,
                            import_module
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table='unsharded_public.story_enclosures',
            src_id_column='story_enclosures_id',
            # 153,858,997 in source table; 16 chunks
            chunk_size=10_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.story_enclosures
                        WHERE story_enclosures_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            story_enclosures_id,
                            stories_id,
                            url,
                            mime_type,
                            length
                    )
                    INSERT INTO sharded_public.story_enclosures (
                        story_enclosures_id,
                        stories_id,
                        url,
                        mime_type,
                        length
                    )
                        SELECT
                            story_enclosures_id::BIGINT,
                            stories_id::BIGINT,
                            url,
                            mime_type,
                            length
                        FROM deleted_rows
                """
            ],
        )

        downloads_id_src_columns = """
            downloads_id,
            feeds_id,
            stories_id,
            parent,
            url,
            host,
            download_time,
            type,
            state,
            path,
            error_message,
            priority,
            sequence,
            extracted
        """
        downloads_id_dst_columns = """
            downloads_id::BIGINT,
            feeds_id::BIGINT,
            stories_id::BIGINT,
            parent,
            url,
            host,
            download_time,
            type::TEXT::public.download_type,
            state::TEXT::public.download_state,
            path,
            error_message,
            priority,
            sequence,
            extracted
        """

        await self._move_table(
            src_table='unsharded_public.downloads_error',
            src_id_column='downloads_id',
            # 114,330,304 in source table; 12 chunks
            chunk_size=10_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.downloads_error
                        WHERE downloads_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING {downloads_id_src_columns}
                    )
                    INSERT INTO sharded_public.downloads_error ({downloads_id_src_columns})
                        SELECT {downloads_id_dst_columns}
                        FROM deleted_rows
                """
            ],
        )

        max_downloads_id = await self.activities.max_column_value('unsharded_public.downloads', 'downloads_id')
        downloads_id_chunk_size = stories_id_chunk_size

        for partition_index in range(int(max_downloads_id / downloads_id_chunk_size) + 1):
            await self._move_table(
                src_table=f'unsharded_public.downloads_success_content_{str(partition_index).zfill(2)}',
                src_id_column='downloads_id',
                # 65,003,792 in source table; 7 chunks
                chunk_size=10_000_000,
                sql_queries=[
                    f"""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.downloads_success_content_{str(partition_index).zfill(2)}
                            WHERE downloads_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                            RETURNING {downloads_id_src_columns}
                        )
                        INSERT INTO sharded_public.downloads_success ({downloads_id_src_columns})
                            SELECT {downloads_id_dst_columns}
                            FROM deleted_rows
                    """
                ],
            )

        for partition_index in range(int(max_downloads_id / downloads_id_chunk_size) + 1):
            await self._move_table(
                src_table=f'unsharded_public.downloads_success_feed_{str(partition_index).zfill(2)}',
                src_id_column='downloads_id',
                # 45,088,116 in source table; 5 chunks
                chunk_size=10_000_000,
                sql_queries=[
                    f"""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.downloads_success_feed_{str(partition_index).zfill(2)}
                            WHERE downloads_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                            RETURNING {downloads_id_src_columns}
                        )
                        INSERT INTO sharded_public.downloads_success ({downloads_id_src_columns})
                            SELECT {downloads_id_dst_columns}
                            FROM deleted_rows
                    """
                ],
            )

        for partition_index in range(int(max_downloads_id / downloads_id_chunk_size) + 1):
            await self._move_table(
                src_table=f'unsharded_public.download_texts_{str(partition_index).zfill(2)}',
                src_id_column='downloads_id',
                # 69,438,480 in source table; 7 chunks
                chunk_size=10_000_000,
                sql_queries=[
                    f"""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.download_texts_{str(partition_index).zfill(2)}
                            WHERE downloads_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                            RETURNING
                                download_texts_id,
                                downloads_id,
                                download_text,
                                download_text_length
                        )
                        INSERT INTO sharded_public.download_texts (
                            download_texts_id,
                            downloads_id,
                            download_text,
                            download_text_length
                        )
                            SELECT
                                download_texts_id,
                                downloads_id,
                                download_text,
                                download_text_length
                            FROM deleted_rows
                    """
                ],
            )

        await self._move_table(
            src_table=f'unsharded_public.topic_stories',
            src_id_column='topic_stories_id',
            # 165,026,730 in source table; 34 chunks
            chunk_size=5_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.topic_stories
                        WHERE topic_stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            topic_stories_id,
                            topics_id,
                            stories_id,
                            link_mined,
                            iteration,
                            link_weight,
                            redirect_url,
                            valid_foreign_rss_story,
                            link_mine_error
                    )
                    INSERT INTO sharded_public.topic_stories (
                        topic_stories_id,
                        topics_id,
                        stories_id,
                        link_mined,
                        iteration,
                        link_weight,
                        redirect_url,
                        valid_foreign_rss_story,
                        link_mine_error
                    )
                        SELECT
                            topic_stories_id::BIGINT,
                            topics_id::BIGINT,
                            stories_id::BIGINT,
                            link_mined,
                            iteration::BIGINT,
                            link_weight,
                            redirect_url,
                            valid_foreign_rss_story,
                            link_mine_error
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table=f'unsharded_public.topic_links',
            src_id_column='topic_links_id',
            # 1,433,314,412 in source table; 29 chunks
            chunk_size=50_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.topic_links
                        WHERE topic_links_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            topic_links_id,
                            topics_id,
                            stories_id,
                            url,
                            redirect_url,
                            ref_stories_id,
                            link_spidered
                    )
                    INSERT INTO sharded_public.topic_links (
                        topic_links_id,
                        topics_id,
                        stories_id,
                        url,
                        redirect_url,
                        ref_stories_id,
                        link_spidered
                    )
                        SELECT
                            topic_links_id::BIGINT,
                            topics_id::BIGINT,
                            stories_id::BIGINT,
                            url,
                            redirect_url,
                            ref_stories_id::BIGINT,
                            link_spidered
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table=f'unsharded_public.topic_fetch_urls',
            src_id_column='topic_fetch_urls_id',
            # 705,821,290 in source table; 36 chunks
            chunk_size=20_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.topic_fetch_urls
                        WHERE topic_fetch_urls_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            topic_fetch_urls_id,
                            topics_id,
                            url,
                            code,
                            fetch_date,
                            state,
                            message,
                            stories_id,
                            assume_match,
                            topic_links_id
                    )
                    INSERT INTO sharded_public.topic_fetch_urls (
                        topic_fetch_urls_id,
                        topics_id,
                        url,
                        code,
                        fetch_date,
                        state,
                        message,
                        stories_id,
                        assume_match,
                        topic_links_id
                    )
                        SELECT
                            topic_fetch_urls_id::BIGINT,
                            topics_id::BIGINT,
                            url,
                            code,
                            fetch_date,
                            state,
                            message,
                            stories_id::BIGINT,
                            assume_match,
                            topic_links_id::BIGINT
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table=f'unsharded_public.topic_posts',
            src_id_column='topic_posts_id',
            # 95,486,494 in source table; 48 chunks
            chunk_size=2_000_000,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_topic_post_days AS
                        SELECT
                            topic_post_days_id::INT,
                            topics_id::INT
                        FROM public.topic_post_days
                        WHERE topic_post_days_id IN (
                            SELECT topic_post_days_id
                            FROM unsharded_public.topic_posts
                            WHERE topic_posts_id BETWEEN {self.__START_ID_MARKER}
                                                 AND     {self.__END_ID_MARKER}
                        )
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.topic_posts
                        USING temp_chunk_topic_post_days
                        WHERE
                            unsharded_public.topic_posts.topic_post_days_id
                                = temp_chunk_topic_post_days.topic_post_days_id AND
                            unsharded_public.topic_posts.topic_posts_id BETWEEN {self.__START_ID_MARKER}
                                                                        AND     {self.__END_ID_MARKER}
                        RETURNING
                            unsharded_public.topic_posts.topic_posts_id,
                            temp_chunk_topic_post_days.topics_id,
                            unsharded_public.topic_posts.topic_post_days_id,
                            unsharded_public.topic_posts.data,
                            unsharded_public.topic_posts.post_id,
                            unsharded_public.topic_posts.content,
                            unsharded_public.topic_posts.publish_date,
                            unsharded_public.topic_posts.author,
                            unsharded_public.topic_posts.channel,
                            unsharded_public.topic_posts.url
                    )
                    INSERT INTO sharded_public.topic_posts (
                        topic_posts_id,
                        topics_id,
                        topic_post_days_id,
                        data,
                        post_id,
                        content,
                        publish_date,
                        author,
                        channel,
                        url
                    )
                        SELECT
                            topic_posts_id::BIGINT,
                            topics_id::BIGINT,
                            topic_post_days_id::BIGINT,
                            data,
                            post_id::TEXT,
                            content,
                            publish_date,
                            author::TEXT,
                            channel::TEXT,
                            url
                        FROM deleted_rows
                """,
                "TRUNCATE temp_chunk_topic_post_days",
                "DROP TABLE temp_chunk_topic_post_days",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_public.topic_post_urls',
            src_id_column='topic_post_urls_id',
            # 50,726,436 in source table; 25 chunks
            chunk_size=2_000_000,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_topic_posts AS
                        SELECT
                            topic_posts_id::INT,
                            topics_id::INT
                        FROM sharded_public.topic_posts
                        WHERE topic_posts_id IN (
                            SELECT topic_posts_id
                            FROM unsharded_public.topic_post_urls
                            WHERE topic_post_urls_id BETWEEN {self.__START_ID_MARKER}
                                                     AND     {self.__END_ID_MARKER}
                        )
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.topic_post_urls
                        USING temp_chunk_topic_posts
                        WHERE
                            unsharded_public.topic_post_urls.topic_posts_id = temp_chunk_topic_posts.topic_posts_id AND
                            unsharded_public.topic_post_urls.topic_post_urls_id BETWEEN {self.__START_ID_MARKER}
                                                                                AND     {self.__END_ID_MARKER}
                        RETURNING
                            unsharded_public.topic_post_urls.topic_post_urls_id,
                            temp_chunk_topic_posts.topics_id,
                            unsharded_public.topic_post_urls.topic_posts_id,
                            unsharded_public.topic_post_urls.url
                    )
                    INSERT INTO sharded_public.topic_post_urls (
                        topic_post_urls_id,
                        topics_id,
                        topic_posts_id,
                        url
                    )
                        SELECT
                            topic_post_urls_id::BIGINT,
                            topics_id,
                            topic_posts_id::BIGINT,
                            url::TEXT
                        FROM deleted_rows
                """,
                "TRUNCATE temp_chunk_topic_posts",
                "DROP TABLE temp_chunk_topic_posts",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_public.topic_seed_urls',
            src_id_column='topic_seed_urls_id',
            # 499,926,808 in source table; 50 chunks
            chunk_size=10_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_public.topic_seed_urls
                        WHERE topic_seed_urls_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            topic_seed_urls_id,
                            topics_id,
                            url,
                            source,
                            stories_id,
                            processed,
                            assume_match,
                            content,
                            guid,
                            title,
                            publish_date,
                            topic_seed_queries_id,
                            topic_post_urls_id
                    )
                    INSERT INTO sharded_public.topic_seed_urls (
                        topic_seed_urls_id,
                        topics_id,
                        url,
                        source,
                        stories_id,
                        processed,
                        assume_match,
                        content,
                        guid,
                        title,
                        publish_date,
                        topic_seed_queries_id,
                        topic_post_urls_id
                    )
                        SELECT
                            topic_seed_urls_id::BIGINT,
                            topics_id::BIGINT,
                            url,
                            source,
                            stories_id::BIGINT,
                            processed,
                            assume_match,
                            content,
                            guid,
                            title,
                            publish_date,
                            topic_seed_queries_id::BIGINT,
                            topic_post_urls_id::BIGINT
                        FROM deleted_rows
                """
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.stories',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_snapshots AS
                        SELECT
                            snapshots_id::INT,
                            topics_id::INT
                        FROM public.snapshots
                        WHERE snapshots_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,

                # snap.stories (topics_id, snapshots_id, stories_id, media_id, guid) also has a unique index, and
                # PostgreSQL doesn't support multiple ON CONFLICT, so let's hope that there are no duplicates in the
                # source table
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.stories
                        USING temp_chunk_snapshots
                        WHERE
                            unsharded_snap.stories.snapshots_id = temp_chunk_snapshots.snapshots_id AND
                            unsharded_snap.stories.snapshots_id BETWEEN {self.__START_ID_MARKER}
                                                                AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_snapshots.topics_id,
                            unsharded_snap.stories.snapshots_id,
                            unsharded_snap.stories.stories_id,
                            unsharded_snap.stories.media_id,
                            unsharded_snap.stories.url,
                            unsharded_snap.stories.guid,
                            unsharded_snap.stories.title,
                            unsharded_snap.stories.publish_date,
                            unsharded_snap.stories.collect_date,
                            unsharded_snap.stories.full_text_rss,
                            unsharded_snap.stories.language
                    )
                    INSERT INTO sharded_snap.stories (
                        topics_id,
                        snapshots_id,
                        stories_id,
                        media_id,
                        url,
                        guid,
                        title,
                        publish_date,
                        collect_date,
                        full_text_rss,
                        language
                    )
                        SELECT
                            topics_id::BIGINT,
                            snapshots_id::BIGINT,
                            stories_id::BIGINT,
                            media_id::BIGINT,
                            url::TEXT,
                            guid::TEXT,
                            title,
                            publish_date,
                            collect_date,
                            full_text_rss,
                            language
                        FROM deleted_rows
                    ON CONFLICT (topics_id, snapshots_id, stories_id) DO NOTHING
                """,
                "TRUNCATE temp_chunk_snapshots",
                "DROP TABLE temp_chunk_snapshots",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.topic_stories',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.topic_stories
                        WHERE snapshots_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            topics_id,
                            snapshots_id,
                            topic_stories_id,
                            stories_id,
                            link_mined,
                            iteration,
                            link_weight,
                            redirect_url,
                            valid_foreign_rss_story
                    )
                    INSERT INTO sharded_snap.topic_stories (
                        topics_id,
                        snapshots_id,
                        topic_stories_id,
                        stories_id,
                        link_mined,
                        iteration,
                        link_weight,
                        redirect_url,
                        valid_foreign_rss_story
                    )
                        SELECT
                            topics_id::BIGINT,
                            snapshots_id::BIGINT,
                            topic_stories_id::BIGINT,
                            stories_id::BIGINT,
                            link_mined,
                            iteration::BIGINT,
                            link_weight,
                            redirect_url,
                            valid_foreign_rss_story
                        FROM deleted_rows
                    ON CONFLICT (topics_id, snapshots_id, stories_id) DO NOTHING
                """
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.topic_links_cross_media',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.topic_links_cross_media
                        WHERE snapshots_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            topics_id,
                            snapshots_id,
                            topic_links_id,
                            stories_id,
                            url,
                            ref_stories_id
                    )
                    INSERT INTO sharded_snap.topic_links_cross_media (
                        topics_id,
                        snapshots_id,
                        topic_links_id,
                        stories_id,
                        url,
                        ref_stories_id
                    )
                        SELECT
                            topics_id::BIGINT,
                            snapshots_id::BIGINT,
                            topic_links_id::BIGINT,
                            stories_id::BIGINT,
                            url,
                            ref_stories_id::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (topics_id, snapshots_id, stories_id, ref_stories_id) DO NOTHING
                """
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.media',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_snapshots AS
                        SELECT
                            snapshots_id::INT,
                            topics_id::INT
                        FROM public.snapshots
                        WHERE snapshots_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.media
                        USING temp_chunk_snapshots
                        WHERE
                            unsharded_snap.media.snapshots_id = temp_chunk_snapshots.snapshots_id AND
                            unsharded_snap.media.snapshots_id BETWEEN {self.__START_ID_MARKER}
                                                              AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_snapshots.topics_id,
                            unsharded_snap.media.snapshots_id,
                            unsharded_snap.media.media_id,
                            unsharded_snap.media.url,
                            unsharded_snap.media.name,
                            unsharded_snap.media.full_text_rss,
                            unsharded_snap.media.foreign_rss_links,
                            unsharded_snap.media.dup_media_id,
                            unsharded_snap.media.is_not_dup
                    )
                    INSERT INTO sharded_snap.media (
                        topics_id,
                        snapshots_id,
                        media_id,
                        url,
                        name,
                        full_text_rss,
                        foreign_rss_links,
                        dup_media_id,
                        is_not_dup
                    )
                        SELECT
                            topics_id::BIGINT,
                            snapshots_id::BIGINT,
                            media_id::BIGINT,
                            url::TEXT,
                            name::TEXT,
                            full_text_rss,
                            foreign_rss_links,
                            dup_media_id::BIGINT,
                            is_not_dup
                        FROM deleted_rows
                    ON CONFLICT (topics_id, snapshots_id, media_id) DO NOTHING
                """,
                "TRUNCATE temp_chunk_snapshots",
                "DROP TABLE temp_chunk_snapshots",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.media_tags_map',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_snapshots AS
                        SELECT
                            snapshots_id::INT,
                            topics_id::INT
                        FROM public.snapshots
                        WHERE snapshots_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.media_tags_map
                        USING temp_chunk_snapshots
                        WHERE
                            unsharded_snap.media_tags_map.snapshots_id = temp_chunk_snapshots.snapshots_id AND
                            unsharded_snap.media_tags_map.snapshots_id BETWEEN {self.__START_ID_MARKER}
                                                                       AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_snapshots.topics_id,
                            unsharded_snap.media_tags_map.snapshots_id,
                            unsharded_snap.media_tags_map.media_tags_map_id,
                            unsharded_snap.media_tags_map.media_id,
                            unsharded_snap.media_tags_map.tags_id
                    )
                    INSERT INTO sharded_snap.media_tags_map (
                        topics_id,
                        snapshots_id,
                        media_tags_map_id,
                        media_id,
                        tags_id
                    )
                        SELECT
                            topics_id::BIGINT,
                            snapshots_id::BIGINT,
                            media_tags_map_id::BIGINT,
                            media_id::BIGINT,
                            tags_id::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (topics_id, snapshots_id, media_id, tags_id) DO NOTHING
                """,
                "TRUNCATE temp_chunk_snapshots",
                "DROP TABLE temp_chunk_snapshots",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.stories_tags_map',
            src_id_column='snapshots_id',
            # MAX(snapshots_id) = 7690 in source table; 52 chunks
            chunk_size=150,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_snapshots AS
                        SELECT
                            snapshots_id::INT,
                            topics_id::INT
                        FROM public.snapshots
                        WHERE snapshots_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.stories_tags_map
                        USING temp_chunk_snapshots
                        WHERE
                            unsharded_snap.stories_tags_map.snapshots_id = temp_chunk_snapshots.snapshots_id AND
                            unsharded_snap.stories_tags_map.snapshots_id BETWEEN {self.__START_ID_MARKER}
                                                                         AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_snapshots.topics_id,
                            unsharded_snap.stories_tags_map.snapshots_id,
                            unsharded_snap.stories_tags_map.stories_tags_map_id,
                            unsharded_snap.stories_tags_map.stories_id,
                            unsharded_snap.stories_tags_map.tags_id
                    )
                    INSERT INTO sharded_snap.stories_tags_map (
                        topics_id,
                        snapshots_id,
                        stories_tags_map_id,
                        stories_id,
                        tags_id
                    )
                        SELECT
                            topics_id::BIGINT,
                            snapshots_id::BIGINT,
                            stories_tags_map_id::BIGINT,
                            stories_id::BIGINT,
                            tags_id::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (topics_id, snapshots_id, stories_id, tags_id) DO NOTHING
                """,
                "TRUNCATE temp_chunk_snapshots",
                "DROP TABLE temp_chunk_snapshots",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.story_links',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_timespans AS
                        SELECT
                            timespans_id::INT,
                            topics_id::INT
                        FROM public.timespans
                        WHERE timespans_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.story_links
                        USING temp_chunk_timespans
                        WHERE
                            unsharded_snap.story_links.timespans_id = temp_chunk_timespans.timespans_id AND
                            unsharded_snap.story_links.timespans_id BETWEEN {self.__START_ID_MARKER}
                                                                    AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_timespans.topics_id,
                            unsharded_snap.story_links.timespans_id,
                            unsharded_snap.story_links.source_stories_id,
                            unsharded_snap.story_links.ref_stories_id
                    )
                    INSERT INTO sharded_snap.story_links (
                        topics_id,
                        timespans_id,
                        source_stories_id,
                        ref_stories_id
                    )
                        SELECT
                            topics_id::BIGINT,
                            timespans_id::BIGINT,
                            source_stories_id::BIGINT,
                            ref_stories_id::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (topics_id, timespans_id, source_stories_id, ref_stories_id) DO NOTHING
                """,
                "TRUNCATE temp_chunk_timespans",
                "DROP TABLE temp_chunk_timespans",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.story_link_counts',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_timespans AS
                        SELECT
                            timespans_id::INT,
                            topics_id::INT
                        FROM public.timespans
                        WHERE timespans_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.story_link_counts
                        USING temp_chunk_timespans
                        WHERE
                            unsharded_snap.story_link_counts.timespans_id = temp_chunk_timespans.timespans_id AND
                            unsharded_snap.story_link_counts.timespans_id BETWEEN {self.__START_ID_MARKER}
                                                                          AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_timespans.topics_id,
                            unsharded_snap.story_link_counts.timespans_id,
                            unsharded_snap.story_link_counts.stories_id,
                            unsharded_snap.story_link_counts.media_inlink_count,
                            unsharded_snap.story_link_counts.inlink_count,
                            unsharded_snap.story_link_counts.outlink_count,
                            unsharded_snap.story_link_counts.facebook_share_count,
                            unsharded_snap.story_link_counts.post_count,
                            unsharded_snap.story_link_counts.author_count,
                            unsharded_snap.story_link_counts.channel_count
                    )
                    INSERT INTO sharded_snap.story_link_counts (
                        topics_id,
                        timespans_id,
                        stories_id,
                        media_inlink_count,
                        inlink_count,
                        outlink_count,
                        facebook_share_count,
                        post_count,
                        author_count,
                        channel_count
                    )
                        SELECT
                            topics_id::BIGINT,
                            timespans_id::BIGINT,
                            stories_id::BIGINT,
                            media_inlink_count::BIGINT,
                            inlink_count::BIGINT,
                            outlink_count::BIGINT,
                            facebook_share_count::BIGINT,
                            post_count::BIGINT,
                            author_count::BIGINT,
                            channel_count::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (topics_id, timespans_id, stories_id) DO NOTHING
                """,
                "TRUNCATE temp_chunk_timespans",
                "DROP TABLE temp_chunk_timespans",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.medium_link_counts',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_timespans AS
                        SELECT
                            timespans_id::INT,
                            topics_id::INT
                        FROM public.timespans
                        WHERE timespans_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.medium_link_counts
                        USING temp_chunk_timespans
                        WHERE
                            unsharded_snap.medium_link_counts.timespans_id = temp_chunk_timespans.timespans_id AND
                            unsharded_snap.medium_link_counts.timespans_id BETWEEN {self.__START_ID_MARKER}
                                                                           AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_timespans.topics_id,
                            unsharded_snap.medium_link_counts.timespans_id,
                            unsharded_snap.medium_link_counts.media_id,
                            unsharded_snap.medium_link_counts.sum_media_inlink_count,
                            unsharded_snap.medium_link_counts.media_inlink_count,
                            unsharded_snap.medium_link_counts.inlink_count,
                            unsharded_snap.medium_link_counts.outlink_count,
                            unsharded_snap.medium_link_counts.story_count,
                            unsharded_snap.medium_link_counts.facebook_share_count,
                            unsharded_snap.medium_link_counts.sum_post_count,
                            unsharded_snap.medium_link_counts.sum_author_count,
                            unsharded_snap.medium_link_counts.sum_channel_count
                    )
                    INSERT INTO sharded_snap.medium_link_counts (
                        topics_id,
                        timespans_id,
                        media_id,
                        sum_media_inlink_count,
                        media_inlink_count,
                        inlink_count,
                        outlink_count,
                        story_count,
                        facebook_share_count,
                        sum_post_count,
                        sum_author_count,
                        sum_channel_count
                    )
                        SELECT
                            topics_id::BIGINT,
                            timespans_id::BIGINT,
                            media_id::BIGINT,
                            sum_media_inlink_count::BIGINT,
                            media_inlink_count::BIGINT,
                            inlink_count::BIGINT,
                            outlink_count::BIGINT,
                            story_count::BIGINT,
                            facebook_share_count::BIGINT,
                            sum_post_count::BIGINT,
                            sum_author_count::BIGINT,
                            sum_channel_count::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (topics_id, timespans_id, media_id) DO NOTHING
                """,
                "TRUNCATE temp_chunk_timespans",
                "DROP TABLE temp_chunk_timespans",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.medium_links',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_timespans AS
                        SELECT
                            timespans_id::INT,
                            topics_id::INT
                        FROM public.timespans
                        WHERE timespans_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.medium_links
                        USING temp_chunk_timespans
                        WHERE
                            unsharded_snap.medium_links.timespans_id = temp_chunk_timespans.timespans_id AND
                            unsharded_snap.medium_links.timespans_id BETWEEN {self.__START_ID_MARKER}
                                                                     AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_timespans.topics_id,
                            unsharded_snap.medium_links.timespans_id,
                            unsharded_snap.medium_links.source_media_id,
                            unsharded_snap.medium_links.ref_media_id,
                            unsharded_snap.medium_links.link_count
                    )
                    INSERT INTO sharded_snap.medium_links (
                        topics_id,
                        timespans_id,
                        source_media_id,
                        ref_media_id,
                        link_count
                    )
                        SELECT
                            topics_id::BIGINT,
                            timespans_id::BIGINT,
                            source_media_id::BIGINT,
                            ref_media_id::BIGINT,
                            link_count::BIGINT
                        FROM deleted_rows
                    ON CONFLICT (topics_id, timespans_id, source_media_id, ref_media_id) DO NOTHING
                """,
                "TRUNCATE temp_chunk_timespans",
                "DROP TABLE temp_chunk_timespans",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.timespan_posts',
            src_id_column='timespans_id',
            # MAX(timespans_id) = 1_362_209 in source table; 28 chunks
            chunk_size=50_000,
            sql_queries=[
                # Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore
                # we create a temporary table first
                f"""
                    CREATE TEMPORARY TABLE temp_chunk_timespans AS
                        SELECT
                            timespans_id::INT,
                            topics_id::INT
                        FROM public.timespans
                        WHERE timespans_id BETWEEN {self.__START_ID_MARKER}
                                           AND     {self.__END_ID_MARKER}
                """,
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.timespan_posts
                        USING temp_chunk_timespans
                        WHERE
                            unsharded_snap.timespan_posts.timespans_id = temp_chunk_timespans.timespans_id AND
                            unsharded_snap.timespan_posts.timespans_id BETWEEN {self.__START_ID_MARKER}
                                                                       AND     {self.__END_ID_MARKER}
                        RETURNING
                            temp_chunk_timespans.topics_id,
                            unsharded_snap.timespan_posts.timespans_id,
                            unsharded_snap.timespan_posts.topic_posts_id
                    )
                    INSERT INTO sharded_snap.timespan_posts (
                        topics_id,
                        timespans_id,
                        topic_posts_id
                    )
                        SELECT
                            topics_id::BIGINT,
                            timespans_id::BIGINT,
                            topic_posts_id::BIGINT
                        FROM deleted_rows
                """,
                "TRUNCATE temp_chunk_timespans",
                "DROP TABLE temp_chunk_timespans",
            ],
        )

        await self._move_table(
            src_table=f'unsharded_snap.live_stories',
            src_id_column='topic_stories_id',
            # MAX(topic_stories_id) = 165_082_931 in source table; 34 chunks
            chunk_size=5_000_000,
            sql_queries=[
                f"""
                    WITH deleted_rows AS (
                        DELETE FROM unsharded_snap.live_stories
                        WHERE topic_stories_id BETWEEN {self.__START_ID_MARKER} AND {self.__END_ID_MARKER}
                        RETURNING
                            topics_id,
                            topic_stories_id,
                            stories_id,
                            media_id,
                            url,
                            guid,
                            title,
                            normalized_title_hash,
                            description,
                            publish_date,
                            collect_date,
                            full_text_rss,
                            language
                    )
                    INSERT INTO sharded_snap.live_stories (
                        topics_id,
                        topic_stories_id,
                        stories_id,
                        media_id,
                        url,
                        guid,
                        title,
                        normalized_title_hash,
                        description,
                        publish_date,
                        collect_date,
                        full_text_rss,
                        language
                    )
                        SELECT
                            topics_id::BIGINT,
                            topic_stories_id::BIGINT,
                            stories_id::BIGINT,
                            media_id::BIGINT,
                            url::TEXT,
                            guid::TEXT,
                            title,
                            normalized_title_hash,
                            description,
                            publish_date,
                            collect_date,
                            full_text_rss,
                            language
                        FROM deleted_rows
                """
            ],
        )
