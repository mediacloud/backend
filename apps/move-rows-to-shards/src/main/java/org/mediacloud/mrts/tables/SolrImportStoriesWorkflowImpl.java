package org.mediacloud.mrts.tables;

import java.util.List;

public class SolrImportStoriesWorkflowImpl extends TableMoveWorkflow implements SolrImportStoriesWorkflow {

    @Override
    public void moveSolrImportStories() {
        this.moveTable(
                "unsharded_public.solr_import_stories",
                "stories_id",
                // Rather small table
                100_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.solr_import_stories
                            WHERE stories_id BETWEEN %s AND %s
                            RETURNING stories_id
                        )
                        INSERT INTO sharded_public.solr_import_stories (stories_id)
                            SELECT stories_id::BIGINT
                            FROM deleted_rows
                        ON CONFLICT (stories_id) DO NOTHING
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
