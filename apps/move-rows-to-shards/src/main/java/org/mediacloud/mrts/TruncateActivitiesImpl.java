package org.mediacloud.mrts;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

public class TruncateActivitiesImpl implements TruncateActivities {

    private static final Logger log = LoggerFactory.getLogger(TruncateActivitiesImpl.class);

    @Override
    public void truncateIfEmpty(String table) {
        if (!table.contains(".")) {
            throw new RuntimeException("Table name must contain schema: " + table);
        }
        if (!table.startsWith("unsharded_")) {
            throw new RuntimeException("Table name must start with 'unsharded_': " + table);
        }

        // FIXME "story_sentences" partitions are huge, so in the interest of speeding up the migration let's just kind
        // of assume that they're empty
        if (table.contains("story_sentences")) {
            log.info("It's one of the 'story_sentences' tables, assuming that it's empty");
        } else {
            log.info("Testing if table '" + table + "' is empty...");
            if (!Database.tableIsEmpty(table)) {
                throw new RuntimeException("Table '" + table + "' is still not empty");
            }
            log.info("Table '" + table + "' is empty");
        }

        log.info("Truncating table '" + table + "'...");
        Database.query(List.of("TRUNCATE " + table));

        log.info("Truncated table '" + table + "'");
    }
}
