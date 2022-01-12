package org.mediacloud.mrts;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.SQLException;
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
        try {
            if (!Database.tableIsEmpty(table)) {
                throw new RuntimeException("Table '" + table + "' is still not empty");
            }
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to test if table is empty: " + e.getMessage());
        }
        log.info("Table '" + table + "' is empty");

        log.info("Truncating table '" + table + "'...");
        try {
            Database.query(List.of("TRUNCATE " + table));
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to truncate table: " + e.getMessage());
        }

        log.info("Truncated table '" + table + "'");
    }
}
