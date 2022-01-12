package org.mediacloud.mrts;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.annotation.Nullable;
import java.sql.SQLException;

public class MinMaxActivitiesImpl implements MinMaxActivities {

    private static final Logger log = LoggerFactory.getLogger(MinMaxActivitiesImpl.class);

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

        Long minValue;
        try {
            minValue = Database.queryLong("SELECT MIN(" + idColumn + ") FROM " + table);
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

        Long maxValue;
        try {
            maxValue = Database.queryLong("SELECT MAX(" + idColumn + ") FROM " + table);
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to select max. value: " + e.getMessage());
        }

        log.info("Max. value of " + table + " (" + idColumn + "): " + maxValue);

        return maxValue;
    }
}
