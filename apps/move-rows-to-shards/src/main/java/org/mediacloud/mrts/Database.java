package org.mediacloud.mrts;

import javax.annotation.Nullable;
import java.sql.*;
import java.util.Arrays;
import java.util.List;

public class Database {

    private final Connection conn;

    public Database() throws SQLException {
        this.conn = DriverManager.getConnection("jdbc:postgresql://postgresql-pgbouncer:6432/mediacloud", "mediacloud", "mediacloud");
        this.conn.setAutoCommit(false);
    }

    public void query(List<String> sqlQueries) throws SQLException {

        // FIXME story_urls exceptions
        List<String> storyUrlsCopiedChunkSqlExcerpts = Arrays.asList(
                "WHERE story_urls_id BETWEEN 1 AND 50000000",
                "WHERE story_urls_id BETWEEN 50000001 AND 100000000",
                "WHERE story_urls_id BETWEEN 100000001 AND 150000000",
                "WHERE story_urls_id BETWEEN 150000001 AND 200000000",
                "WHERE story_urls_id BETWEEN 200000001 AND 250000000",
                "WHERE story_urls_id BETWEEN 250000001 AND 300000000",
                "WHERE story_urls_id BETWEEN 300000001 AND 350000000",
                "WHERE story_urls_id BETWEEN 350000001 AND 400000000",
                "WHERE story_urls_id BETWEEN 400000001 AND 450000000",
                "WHERE story_urls_id BETWEEN 450000001 AND 500000000",
                "WHERE story_urls_id BETWEEN 500000001 AND 550000000",
                "WHERE story_urls_id BETWEEN 600000001 AND 650000000",
                "WHERE story_urls_id BETWEEN 650000001 AND 700000000",
                "WHERE story_urls_id BETWEEN 700000001 AND 750000000",
                "WHERE story_urls_id BETWEEN 750000001 AND 800000000",
                "WHERE story_urls_id BETWEEN 800000001 AND 850000000",
                "WHERE story_urls_id BETWEEN 850000001 AND 900000000",
                "WHERE story_urls_id BETWEEN 900000001 AND 950000000",
                "WHERE story_urls_id BETWEEN 950000001 AND 1000000000",
                "WHERE story_urls_id BETWEEN 1000000001 AND 1050000000",
                "WHERE story_urls_id BETWEEN 1050000001 AND 1100000000",
                "WHERE story_urls_id BETWEEN 1100000001 AND 1150000000",
                "WHERE story_urls_id BETWEEN 1150000001 AND 1200000000",
                "WHERE story_urls_id BETWEEN 1200000001 AND 1250000000",
                "WHERE story_urls_id BETWEEN 1250000001 AND 1300000000",
                "WHERE story_urls_id BETWEEN 1300000001 AND 1350000000",
                "WHERE story_urls_id BETWEEN 1350000001 AND 1400000000",
                "WHERE story_urls_id BETWEEN 1400000001 AND 1450000000",
                "WHERE story_urls_id BETWEEN 2050000001 AND 2100000000",
                "WHERE story_urls_id BETWEEN 2100000001 AND 2150000000",
                "WHERE story_urls_id BETWEEN 2150000001 AND 2200000000",
                "WHERE story_urls_id BETWEEN 2300000001 AND 2350000000"
        );

        boolean sqlQueryIsStoryUrlsException = false;
        if (sqlQueries.size() == 1) {
            String sqlQuery = sqlQueries.get(0);

            for (String excerpt : storyUrlsCopiedChunkSqlExcerpts) {
                if (sqlQuery.contains(excerpt)) {
                    sqlQueryIsStoryUrlsException = true;
                    break;
                }
            }
        }

        if (!sqlQueryIsStoryUrlsException) {
            Statement stmt = this.conn.createStatement();
            for (String query : sqlQueries) {
                stmt.executeUpdate(query);
            }
            this.conn.commit();
        }
    }

    public @Nullable
    Long queryLong(String sqlQuery) throws SQLException {
        Statement stmt = this.conn.createStatement();
        ResultSet rs = stmt.executeQuery(sqlQuery);
        this.conn.commit();

        if (rs.next()) {
            return rs.getLong(1);
        } else {
            return null;
        }
    }

    public boolean tableIsEmpty(String table) throws SQLException {
        Statement stmt = this.conn.createStatement();
        //noinspection SqlNoDataSourceInspection
        ResultSet rs = stmt.executeQuery("SELECT * FROM " + table + " LIMIT 1");
        this.conn.commit();
        return !rs.next();
    }
}
