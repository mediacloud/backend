


-- Rename "cd" to "snap" which somehow didn't happen in 4563-4564 migration
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'cd') THEN
        ALTER SCHEMA cd RENAME TO snap;
    END IF;
END$$;


