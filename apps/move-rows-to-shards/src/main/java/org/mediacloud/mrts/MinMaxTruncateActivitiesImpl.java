package org.mediacloud.mrts;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.annotation.Nullable;
import java.sql.SQLException;
import java.util.List;

public class MinMaxTruncateActivitiesImpl implements MinMaxTruncateActivities {

    private static final Logger log = LoggerFactory.getLogger(MinMaxTruncateActivitiesImpl.class);

    private void testTableIdColumn(String table, String idColumn) {
        if (!table.contains(".")) {
            throw new RuntimeException("Table name must contain schema: " + table);
        }
        if (!table.startsWith("unsharded_")) {
            throw new RuntimeException("Table name must start with 'unsharded_': " + table);
        }
        if (idColumn.contains(".")) {
            throw new RuntimeException("Invalid ID column name: " + idColumn);
        }
    }

    @Nullable
    @Override
    public Long minColumnValue(String table, String idColumn) {
        log.info("Getting min. value of " + table + " (" + idColumn + ")");

        this.testTableIdColumn(table, idColumn);

        Database db;
        try {
            db = new Database();
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to connect to database: " + e.getMessage());
        }

        Long minValue;
        try {
            minValue = db.queryLong("SELECT MIN(" + idColumn + ") FROM " + table);
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to select min. value: " + e.getMessage());
        }

        log.info("Min. value of " + table + " (" + idColumn + "): " + minValue);

        return minValue;
    }

    @Nullable
    @Override
    public Long maxColumnValue(String table, String idColumn) {
        log.info("Getting max. value of " + table + " (" + idColumn + ")");

        this.testTableIdColumn(table, idColumn);

        Database db;
        try {
            db = new Database();
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to connect to database: " + e.getMessage());
        }

        Long maxValue;
        try {
            maxValue = db.queryLong("SELECT MAX(" + idColumn + ") FROM " + table);
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to select max. value: " + e.getMessage());
        }

        log.info("Max. value of " + table + " (" + idColumn + "): " + maxValue);

        return maxValue;
    }

    @Override
    public void truncateIfEmpty(String table) {
        if (!table.contains(".")) {
            throw new RuntimeException("Table name must contain schema: " + table);
        }
        if (!table.startsWith("unsharded_")) {
            throw new RuntimeException("Table name must start with 'unsharded_': " + table);
        }

        Database db;
        try {
            db = new Database();
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to connect to database: " + e.getMessage());
        }

        log.info("Testing if table '" + table + "' is empty...");
        try {
            if (!db.tableIsEmpty(table)) {
                throw new RuntimeException("Table '" + table + "' is still not empty");
            }
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to test if table is empty: " + e.getMessage());
        }
        log.info("Table '" + table + "' is empty");

        log.info("Truncating table '" + table + "'...");
        try {
            db.query(List.of("TRUNCATE " + table));
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to truncate table: " + e.getMessage());
        }
        log.info("Truncated table '" + table + "'");
    }

    @Override
    public void noOp(String table) {
        // no-op
    }
}
