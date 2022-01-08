package org.mediacloud.mrts;

import javax.annotation.Nullable;
import java.sql.*;
import java.util.List;

public class Database {

    private final Connection conn;

    public Database() throws SQLException {
        this.conn = DriverManager.getConnection("jdbc:postgresql://postgresql-pgbouncer:6432/mediacloud", "mediacloud", "mediacloud");
        this.conn.setAutoCommit(false);
    }

    public void query(List<String> sqlQueries) throws SQLException {
        Statement stmt = this.conn.createStatement();
        for (String query : sqlQueries) {
            stmt.executeUpdate(query);
        }
        this.conn.commit();
    }

    public @Nullable
    Integer queryInt(String sqlQuery) throws SQLException {
        Statement stmt = this.conn.createStatement();
        ResultSet rs = stmt.executeQuery(sqlQuery);
        this.conn.commit();

        if (rs.next()) {
            return rs.getInt(1);
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
