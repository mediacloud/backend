--
-- dkLab PostgreSQL 8.3 ALTER ENUM emulation.
-- See http://en.dklab.ru/lib/dklab_postgresql_enum/
--
-- (C) Dmitry Koterov, 2009
-- This code is BSD licensed.
--

CREATE SCHEMA enum AUTHORIZATION postgres;
--
-- Definition for function enum_add (OID = 24591) : 
--
SET search_path = enum, pg_catalog;
SET check_function_bodies = false;
CREATE FUNCTION enum.enum_add (enum_name character varying, enum_elem character varying) RETURNS void
AS 
$body$
BEGIN
    INSERT INTO pg_enum(enumtypid, enumlabel) VALUES(
        (SELECT oid FROM pg_type WHERE typtype='e' AND typname=enum_name), 
        enum_elem
    );
END;
$body$
    LANGUAGE plpgsql;
--
-- Definition for function enum_del (OID = 24592) : 
--
CREATE FUNCTION enum.enum_del (enum_name character varying, enum_elem character varying) RETURNS void
AS 
$body$
DECLARE
    type_oid INTEGER;
    rec RECORD;
    sql VARCHAR;
    ret INTEGER;
BEGIN
    SELECT pg_type.oid
    FROM pg_type 
    WHERE typtype = 'e' AND typname = enum_name
    INTO type_oid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot find a enum: %', enum_name; 
    END IF;
                             
    -- Check column DEFAULT value references.
    SELECT *
    FROM 
        pg_attrdef
        JOIN pg_attribute ON attnum = adnum AND atttypid = type_oid
        JOIN pg_class ON pg_class.oid = attrelid
        JOIN pg_namespace ON pg_namespace.oid = relnamespace
    WHERE   
        adsrc = quote_literal(enum_elem) || '::' || quote_ident(enum_name)
    LIMIT 1
    INTO rec; 
    
    IF FOUND THEN
        RAISE EXCEPTION 
            'Cannot delete the ENUM element %.%: column %.%.% has DEFAULT value of ''%''',
            quote_ident(enum_name), quote_ident(enum_elem),
            quote_ident(rec.nspname), quote_ident(rec.relname),
            rec.attname, quote_ident(enum_elem);
    END IF;
    
    -- Check data references.
    FOR rec IN 
        SELECT *
        FROM 
            pg_attribute
            JOIN pg_class ON pg_class.oid = attrelid
            JOIN pg_namespace ON pg_namespace.oid = relnamespace
        WHERE 
            atttypid = type_oid
            AND relkind = 'r'
    LOOP
        sql := 
            'SELECT 1 FROM ONLY ' 
            || quote_ident(rec.nspname) || '.'
            || quote_ident(rec.relname) || ' '
            || ' WHERE ' 
            || quote_ident(rec.attname) || ' = '
            || quote_literal(enum_elem)
            || ' LIMIT 1';
        EXECUTE sql INTO ret;
        IF ret IS NOT NULL THEN
            RAISE EXCEPTION 
                'Cannot delete the ENUM element %.%: column %.%.% contains references',
                quote_ident(enum_name), quote_ident(enum_elem),
                quote_ident(rec.nspname), quote_ident(rec.relname),
                rec.attname;
        END IF;
    END LOOP;    
    
    -- OK. We may delete.
    DELETE FROM pg_enum WHERE enumtypid = type_oid AND enumlabel = enum_elem;
END;
$body$
    LANGUAGE plpgsql;
--
-- Comments
--
COMMENT ON FUNCTION enum.enum_add (enum_name character varying, enum_elem character varying) IS 'Inserts a new ENUM element wthout re-creating the whole type.';
COMMENT ON FUNCTION enum.enum_del (enum_name character varying, enum_elem character varying) IS 'Removes the ENUM element "on the fly". Check references to the ENUM element in database''s tables before the deletion and throws an exception if the element cannot be deleted.';
