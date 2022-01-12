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

        log.info("Testing if table '" + table + "' is empty...");
        if (!Database.tableIsEmpty(table)) {
            throw new RuntimeException("Table '" + table + "' is still not empty");
        }
        log.info("Table '" + table + "' is empty");

        log.info("Truncating table '" + table + "'...");
        Database.query(List.of("TRUNCATE " + table));

        log.info("Truncated table '" + table + "'");
    }
}
