BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';

    return true;
    
END;
$$
LANGUAGE 'plpgsql';