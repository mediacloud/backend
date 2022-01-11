package org.mediacloud.mrts.tables;

import java.util.List;

public class SolrImportedStoriesWorkflowImpl extends TableMoveWorkflow implements SolrImportedStoriesWorkflow {

    @Override
    public void moveSolrImportedStories() {
        this.moveTable(
                "unsharded_public.solr_imported_stories",
                "stories_id",
                // MAX(stories_id) = 2,119,343,981
                5_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.solr_imported_stories
                            WHERE stories_id BETWEEN %s AND %s
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
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
