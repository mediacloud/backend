package org.mediacloud.mrts;

import javax.annotation.Nullable;
import java.sql.*;
import java.util.List;

public class Database {

    private static Connection getConnection() {
        Connection conn;
        try {
            conn = DriverManager.getConnection("jdbc:postgresql://postgresql-server:5432/mediacloud", "mediacloud", "mediacloud");
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to connect to database: " + e.getMessage());
        }
        return conn;
    }

    public static void query(List<String> sqlQueries) {
        Connection conn = getConnection();
        Statement stmt = null;
        try {
            stmt = conn.createStatement();
            for (String query : sqlQueries) {
                stmt.executeUpdate(query);
            }
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to run queries " + sqlQueries + ": " + e.getMessage());
        } finally {
            try {
                if (stmt != null) {
                    stmt.close();
                }
                conn.close();
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
    }

    public static @Nullable
    Long queryLong(String sqlQuery) {
        Connection conn = getConnection();
        Statement stmt = null;
        ResultSet rs = null;
        Long result;
        try {
            stmt = conn.createStatement();
            rs = stmt.executeQuery(sqlQuery);

            if (rs.next()) {
                result = rs.getLong(1);
            } else {
                result = null;
            }
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to run query " + sqlQuery + ": " + e.getMessage());
        } finally {
            try {
                if (rs != null) {
                    rs.close();
                }
                if (stmt != null) {
                    stmt.close();
                }
                conn.close();
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }

        return result;
    }

    public static boolean tableIsEmpty(String table) {
        Connection conn = getConnection();
        Statement stmt = null;
        ResultSet rs = null;
        boolean isEmpty;

        try {
            stmt = conn.createStatement();
            //noinspection SqlNoDataSourceInspection
            rs = stmt.executeQuery("SELECT * FROM " + table + " LIMIT 1");
            isEmpty = !rs.next();
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Unable to test if table is empty: " + e.getMessage());
        } finally {
            try {
                if (rs != null) {
                    rs.close();
                }
                if (stmt != null) {
                    stmt.close();
                }
                conn.close();
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }

        return isEmpty;
    }
}
