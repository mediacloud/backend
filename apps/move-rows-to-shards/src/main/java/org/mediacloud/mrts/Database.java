package org.mediacloud.mrts;

import javax.annotation.Nullable;
import java.sql.*;
import java.util.List;

public class Database {

    private final Connection conn;

    public Database() throws SQLException {
        this.conn = DriverManager.getConnection("jdbc:postgresql://postgresql-server:5432/mediacloud", "mediacloud", "mediacloud");
    }

    public void query(List<String> sqlQueries) throws SQLException {
        Statement stmt = this.conn.createStatement();
        for (String query : sqlQueries) {
            stmt.executeUpdate(query);
        }
    }

    public @Nullable
    Long queryLong(String sqlQuery) throws SQLException {
        Statement stmt = this.conn.createStatement();
        ResultSet rs = stmt.executeQuery(sqlQuery);

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
        return !rs.next();
    }
}
