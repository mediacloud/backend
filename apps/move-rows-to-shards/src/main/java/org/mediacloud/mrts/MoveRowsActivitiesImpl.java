package org.mediacloud.mrts;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.SQLException;
import java.util.List;

public class MoveRowsActivitiesImpl implements MoveRowsActivities {

    private static final Logger log = LoggerFactory.getLogger(MinMaxTruncateActivitiesImpl.class);

    @Override
    public String runQueriesInTransaction(List<String> sqlQueries) {
        Database db;
        try {
            db = new Database();
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to connect to database: " + e.getMessage());
        }

        log.info("Executing SQL queries: " + sqlQueries);

        try {
            db.query(sqlQueries);
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to execute SQL queries: " + e.getMessage());
        }

        log.info("Executed SQL queries: " + sqlQueries);

        // Not sure how to do Promise<void>, and it's late at night already
        return "";
    }
}
