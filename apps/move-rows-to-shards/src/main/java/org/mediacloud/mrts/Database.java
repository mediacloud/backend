package org.mediacloud.mrts;

import javax.annotation.Nullable;
import java.sql.*;
import java.util.List;

public class Database {

    private static Connection getConnection() throws SQLException {
        return DriverManager.getConnection("jdbc:postgresql://postgresql-server:5432/mediacloud", "mediacloud", "mediacloud");
    }

    public static void query(List<String> sqlQueries) throws SQLException {
        Connection conn = getConnection();
        Statement stmt = conn.createStatement();
        for (String query : sqlQueries) {
            stmt.executeUpdate(query);
        }
        stmt.close();
        conn.close();
    }

    public static @Nullable
    Long queryLong(String sqlQuery) throws SQLException {
        Connection conn = getConnection();
        Statement stmt = conn.createStatement();
        ResultSet rs = stmt.executeQuery(sqlQuery);

        Long result;

        if (rs.next()) {
            result = rs.getLong(1);
        } else {
            result = null;
        }

        rs.close();
        stmt.close();
        conn.close();

        return result;
    }

    public static boolean tableIsEmpty(String table) throws SQLException {
        Connection conn = getConnection();
        Statement stmt = conn.createStatement();
        //noinspection SqlNoDataSourceInspection
        ResultSet rs = stmt.executeQuery("SELECT * FROM " + table + " LIMIT 1");
        boolean isEmpty = !rs.next();

        rs.close();
        stmt.close();
        conn.close();

        return isEmpty;
    }
}
