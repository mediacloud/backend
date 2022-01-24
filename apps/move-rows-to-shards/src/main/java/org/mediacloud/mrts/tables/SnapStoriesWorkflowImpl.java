package org.mediacloud.mrts.tables;

import java.util.Arrays;

public class SnapStoriesWorkflowImpl extends TableMoveWorkflow implements SnapStoriesWorkflow {

    @Override
    public void moveSnapStories() {
        this.moveTable(
                "unsharded_snap.stories",
                "snapshots_id",
                // MAX(snapshots_id) = 7690 in source table
                10,
                Arrays.asList(
                        // Citus doesn't like it when we join local (unsharded) and distributed tables in this case
                        // therefore we create a temporary table first
                        String.format("""
                                CREATE TEMPORARY TABLE temp_chunk_snapshots AS
                                    SELECT
                                        snapshots_id::INT,
                                        topics_id::INT
                                    FROM public.snapshots
                                    WHERE snapshots_id BETWEEN %s AND %s
                                """, START_ID_MARKER, END_ID_MARKER),

                        // snap.stories (topics_id, snapshots_id, stories_id, media_id, guid) also has a unique index,
                        // and PostgreSQL doesn't support multiple ON CONFLICT, so let's hope that there are no
                        // duplicates in the source table
                        String.format("""
                                WITH deleted_rows AS (
                                    DELETE FROM unsharded_snap.stories
                                    USING temp_chunk_snapshots
                                    WHERE
                                        unsharded_snap.stories.snapshots_id
                                            = temp_chunk_snapshots.snapshots_id AND
                                        unsharded_snap.stories.snapshots_id BETWEEN %s AND %s
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
                                """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_snapshots",
                        "DROP TABLE temp_chunk_snapshots"
                )
        );
    }
}
