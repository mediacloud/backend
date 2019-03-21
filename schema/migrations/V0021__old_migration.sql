


DO $$
BEGIN
    IF NOT EXISTS (

        -- No raw_downloads.object_id => downloads.downloads_id foreign key?
        SELECT 1
        FROM information_schema.table_constraints tc
            INNER JOIN information_schema.constraint_column_usage ccu
                USING (constraint_catalog, constraint_schema, constraint_name)
            INNER JOIN information_schema.key_column_usage kcu
                USING (constraint_catalog, constraint_schema, constraint_name)
        WHERE constraint_type = 'FOREIGN KEY'
          AND tc.table_name = 'raw_downloads'
          AND kcu.column_name = 'object_id'
          AND ccu.table_name = 'downloads'
          AND ccu.column_name = 'downloads_id'

    ) THEN

        -- Re-add foreign key
        ALTER TABLE raw_downloads
            ADD CONSTRAINT raw_downloads_downloads_id_fkey
            FOREIGN KEY (object_id) REFERENCES downloads(downloads_id) ON DELETE CASCADE;

    END IF;
END;
$$;


