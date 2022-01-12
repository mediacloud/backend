package org.mediacloud.mrts;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.SQLException;
import java.util.List;

public class MoveRowsActivitiesImpl implements MoveRowsActivities {

    private static final Logger log = LoggerFactory.getLogger(MinMaxActivitiesImpl.class);

    @Override
    public void runQueriesInTransaction(List<String> sqlQueries) {
        log.info("Executing SQL queries: " + sqlQueries);

        try {
            Database.query(sqlQueries);
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to execute SQL queries: " + e.getMessage());
        }

        log.info("Executed SQL queries: " + sqlQueries);
    }
}
