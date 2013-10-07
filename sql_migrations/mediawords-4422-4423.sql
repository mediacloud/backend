--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4422 and 4423.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4422, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4423, import this SQL file:
--
--     psql mediacloud < mediawords-4422-4423.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Create the new activity table
CREATE TABLE activities (
    activities_id       SERIAL          PRIMARY KEY,

    -- Activity's name (e.g. "media_edit", "story_edit", etc.)
    name                VARCHAR(255)    NOT NULL
                                        CONSTRAINT activities_name_can_not_contain_spaces CHECK(name NOT LIKE '% %'),

    -- When did the activity happen
    creation_date       TIMESTAMP       NOT NULL DEFAULT LOCALTIMESTAMP,

    -- User that executed the activity, either:
    --     * user's email from "auth_users.email" (e.g. "lvaliukas@cyber.law.harvard.edu", or
    --     * username that initiated the action (e.g. "system:lvaliukas")
    -- (store user's email instead of ID in case the user gets deleted)
    user_identifier     VARCHAR(255)    NOT NULL,

    -- Indexed ID of the object that was modified in some way by the activity
    -- (e.g. media's ID "media_edit" or story's ID in "story_edit")
    object_id           BIGINT          NULL,

    -- User-provided reason explaining why the activity was made
    reason              TEXT            NULL,

    -- Other free-form data describing the action in the JSON format
    -- (e.g.: '{ "field": "name", "old_value": "Foo.", "new_value": "Bar." }')
    -- FIXME: has potential to use 'JSON' type instead of 'TEXT' in
    -- PostgreSQL 9.2+
    description_json    TEXT            NOT NULL DEFAULT '{ }'

);

CREATE INDEX activities_name ON activities (name);
CREATE INDEX activities_creation_date ON activities (creation_date);
CREATE INDEX activities_user_identifier ON activities (user_identifier);
CREATE INDEX activities_object_id ON activities (object_id);


-- Migrate "media_edits" to "activities"
INSERT INTO activities
    (
        name,
        creation_date,
        user_identifier,
        object_id,
        reason,
        description_json
    )
    SELECT
        'media_edit',
        edit_timestamp,
        users_email,
        media_id,
        reason,
        '{ "field": "' || REPLACE(edited_field, '"', '\"') || '", '
            || '"new_value": "' || REPLACE(new_value, '"', '\"') || '", '
            || '"old_value": "' || REPLACE(old_value, '"', '\"') || '" }'
    FROM media_edits
    ORDER BY media_edits_id;


-- Migrate "story_edits" to "activities"
INSERT INTO activities
    (
        name,
        creation_date,
        user_identifier,
        object_id,
        reason,
        description_json
    )
    SELECT
        'story_edit',
        edit_timestamp,
        users_email,
        stories_id,
        reason,
        '{ "field": "' || REPLACE(edited_field, '"', '\"') || '", '
            || '"new_value": "' || REPLACE(new_value, '"', '\"') || '", '
            || '"old_value": "' || REPLACE(old_value, '"', '\"') || '" }'
    FROM story_edits
    ORDER BY story_edits_id;


-- Drop the old tables
DROP TABLE media_edits;
DROP TABLE story_edits;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4423;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

