--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4407 and 4408.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4407, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4408, import this SQL file:
--
--     psql mediacloud < mediawords-4407-4408.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP FUNCTION is_stop_stem("size" TEXT, stem TEXT);

DROP INDEX relative_file_paths_old_format_to_verify;

DROP TABLE stopwords_tiny;

DROP TABLE stopword_stems_tiny;

DROP TABLE stopwords_short;

DROP TABLE stopword_stems_short;

DROP TABLE stopwords_long;

DROP TABLE stopword_stems_long;

CREATE TABLE feedless_stories (
	stories_id integer,
	media_id integer
);

CREATE TABLE auth_users (
	users_id SERIAL  PRIMARY KEY,
	email TEXT    UNIQUE NOT NULL,
	password_hash TEXT    NOT NULL CONSTRAINT password_hash_sha256 CHECK(LENGTH(password_hash) = 137),
	full_name TEXT NOT NULL,
	notes TEXT,
	active BOOLEAN NOT NULL DEFAULT true,
	password_reset_token_hash TEXT UNIQUE NULL CONSTRAINT password_reset_token_hash_sha256 CHECK(LENGTH(password_reset_token_hash) = 137 OR password_reset_token_hash IS NULL),
	last_unsuccessful_login_attempt TIMESTAMP NOT NULL DEFAULT TIMESTAMP 'epoch'
);

CREATE TABLE auth_roles (
	roles_id SERIAL  PRIMARY KEY,
	"role" TEXT    UNIQUE NOT NULL CONSTRAINT role_name_can_not_contain_spaces CHECK(role NOT LIKE '% %'),
	description TEXT NOT NULL
);

CREATE TABLE auth_users_roles_map (
	auth_users_roles_map SERIAL      PRIMARY KEY,
	users_id INTEGER     NOT NULL REFERENCES auth_users(users_id)
                                        ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,
	roles_id INTEGER     NOT NULL REFERENCES auth_roles(roles_id)
                                        ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE
);

CREATE TABLE media_edits (
	media_edits_id SERIAL      PRIMARY KEY,
	edit_timestamp TIMESTAMP   NOT NULL DEFAULT LOCALTIMESTAMP,
	edited_field VARCHAR(64) NOT NULL    
                                    CONSTRAINT edited_field_not_empty CHECK(LENGTH(edited_field) > 0),
	old_value TEXT NOT NULL,
	new_value TEXT NOT NULL,
	reason TEXT        NOT NULL
                                    CONSTRAINT reason_not_empty CHECK(LENGTH(reason) > 0),
	users_email TEXT        NOT NULL REFERENCES auth_users(email)
                                    ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE
);

CREATE TABLE story_edits (
	story_edits_id SERIAL      PRIMARY KEY,
	stories_id INT         NOT NULL REFERENCES stories(stories_id)
                                    
                                    ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE,
	edit_timestamp TIMESTAMP   NOT NULL DEFAULT LOCALTIMESTAMP,
	edited_field VARCHAR(64) NOT NULL    
                                    CONSTRAINT edited_field_not_empty CHECK(LENGTH(edited_field) > 0),
	old_value TEXT NOT NULL,
	new_value TEXT NOT NULL,
	reason TEXT        NOT NULL
                                    CONSTRAINT reason_not_empty CHECK(LENGTH(reason) > 0),
	users_email TEXT        NOT NULL REFERENCES auth_users(email)
                                    ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE
);

ALTER TABLE feeds
	ADD COLUMN feed_status feed_feed_status    not null DEFAULT 'active',
	ALTER COLUMN feeds_id TYPE serial              primary key /* TYPE change - table: feeds original: serial          primary key new: serial              primary key */,
	ALTER COLUMN media_id TYPE int                 not null references media on delete cascade /* TYPE change - table: feeds original: int             not null references media on delete cascade new: int                 not null references media on delete cascade */,
	ALTER COLUMN feed_type TYPE feed_feed_type      not null /* TYPE change - table: feeds original: feed_feed_type  not null new: feed_feed_type      not null */;

ALTER TABLE dashboard_topics
	ADD COLUMN "language" varchar(3) NOT NULL;

ALTER TABLE stories
	ADD COLUMN "language" varchar(3);

ALTER TABLE story_sentences
	ADD COLUMN "language" varchar(3);

ALTER TABLE story_sentence_words
	ADD COLUMN "language" varchar(3);

ALTER TABLE daily_words
	ADD COLUMN "language" varchar(3) NOT NULL;

ALTER TABLE weekly_words
	ADD COLUMN "language" varchar(3) NOT NULL;

ALTER TABLE top_500_weekly_words
	ADD COLUMN "language" varchar(3) NOT NULL;

ALTER TABLE daily_country_counts
	ADD COLUMN "language" varchar(3) NOT NULL;

ALTER TABLE daily_author_words
	ADD COLUMN "language" varchar(3) NOT NULL,
	ALTER COLUMN daily_author_words_id TYPE serial                  primary key /* TYPE change - table: daily_author_words original: serial primary key new: serial                  primary key */,
	ALTER COLUMN authors_id TYPE integer                 not null references authors on delete cascade /* TYPE change - table: daily_author_words original: integer not null references authors on delete cascade new: integer                 not null references authors on delete cascade */,
	ALTER COLUMN media_sets_id TYPE integer                 not null references media_sets on delete cascade /* TYPE change - table: daily_author_words original: integer not null references media_sets on delete cascade new: integer                 not null references media_sets on delete cascade */;

ALTER TABLE weekly_author_words
	ADD COLUMN "language" varchar(3) NOT NULL;

ALTER TABLE top_500_weekly_author_words
	ADD COLUMN "language" varchar(3) NOT NULL;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4408;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

ALTER TABLE auth_users_roles_map
	ADD CONSTRAINT no_duplicate_entries UNIQUE (users_id, roles_id);

CREATE INDEX stories_language ON stories (language);

CREATE INDEX story_sentences_language ON story_sentences (language);

CREATE INDEX feedless_stories_story ON feedless_stories USING btree (stories_id);

CREATE INDEX auth_users_roles_map_users_id_roles_id ON auth_users_roles_map (users_id, roles_id);

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

