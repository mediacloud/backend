package org.mediacloud.mrts.tables;

import java.util.List;

public class ScrapedStoriesWorkflowImpl extends TableMoveWorkflow implements ScrapedStoriesWorkflow {

    @Override
    public void moveScrapedStories() {
        this.moveTable(
                "unsharded_public.scraped_stories",
                "scraped_stories_id",
                // Rather small table
                100_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.scraped_stories
                            WHERE scraped_stories_id BETWEEN %s AND %s
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
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
