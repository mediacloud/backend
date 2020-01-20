--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4733 and 4734.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4733, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4734, import this SQL file:
--
--     psql mediacloud < mediawords-4733-4734.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


--
-- Enclosures added to the story's feed item
--
CREATE TABLE story_enclosures (
    story_enclosures_id     BIGSERIAL   PRIMARY KEY,
    stories_id              INT         NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    -- Podcast enclosure URL
    url                     TEXT        NOT NULL,

    -- RSS spec says that enclosure's "length" and "type" are required too but
    -- I guess some podcasts don't care that much about specs so both are
    -- allowed to be NULL:

    -- MIME type as reported by <enclosure />
    mime_type               CITEXT      NULL,

    -- Length in bytes as reported by <enclosure />
    length                  BIGINT      NULL
);

CREATE UNIQUE INDEX story_enclosures_stories_id_url
    ON story_enclosures (stories_id, url);


--
-- Audio file codec; keep in sync with "_SUPPORTED_NATIVE_AUDIO_CODECS" constant
-- (https://cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.v1p1beta1)
--
CREATE TYPE podcast_episodes_audio_codec AS ENUM (
    'LINEAR16',
    'FLAC',
    'MULAW',
    'OGG_OPUS',
    'MP3'
);


--
-- Podcast story episodes (derived from enclosures)
--
CREATE TABLE podcast_episodes (
    podcast_episodes_id     BIGSERIAL   PRIMARY KEY,
    stories_id              INT         NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    -- Enclosure that the episode was derived from
    story_enclosures_id     BIGINT      NOT NULL
                                            REFERENCES story_enclosures (story_enclosures_id)
                                            ON DELETE CASCADE,

    -- Google Cloud Storage URI where the audio file is located at
    gcs_uri                 TEXT        NOT NULL
                                            CONSTRAINT gcs_uri_has_gs_prefix
                                            CHECK(gcs_uri LIKE 'gs://%'),

    -- Duration (in seconds)
    duration                INT         NOT NULL
                                            CONSTRAINT duration_is_positive
                                            CHECK(duration > 0),

    -- Audio codec as determined by transcoder
    codec                   podcast_episodes_audio_codec  NOT NULL,

    -- Audio sample rate (Hz) as determined by transcoder
    sample_rate             INT         NOT NULL
                                            CONSTRAINT sample_rate_looks_reasonable
                                            CHECK(sample_rate > 1000),

    -- BCP 47 language identifier
    -- (https://cloud.google.com/speech-to-text/docs/languages)
    bcp47_language_code     CITEXT      NOT NULL
                                            CONSTRAINT bcp47_language_code_looks_reasonable
                                            CHECK(
                                                bcp47_language_code LIKE '%-%'
                                             OR bcp47_language_code = 'zh'
                                            )

);

-- Only one episode per story
CREATE UNIQUE INDEX podcast_episodes_stories_id
    ON podcast_episodes (stories_id);


--
-- Podcast episode transcription operations
--
CREATE TABLE podcast_episode_operations (
    podcast_episode_operations_id   BIGSERIAL   PRIMARY KEY,
    stories_id                      INT         NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    -- Podcast that is being transcribed
    podcast_episodes_id     BIGINT  NOT NULL
                                        REFERENCES podcast_episodes (podcast_episodes_id)
                                        ON DELETE CASCADE,

    -- Speech API operation ID to be used for retrieving transcription
    speech_operation_id     TEXT    NOT NULL,

    -- The soonest timestamp when this operation's results should be attempted to be fetched
    fetch_results_at        TIMESTAMP WITH TIME ZONE    NOT NULL

);

-- Only one operation per story
CREATE UNIQUE INDEX podcast_episode_operations_stories_id
    ON podcast_episode_operations (stories_id);

-- Only one operation per episode
CREATE UNIQUE INDEX podcast_episode_operations_podcast_episodes_id
    ON podcast_episode_operations (podcast_episodes_id);

-- "podcast-poll-due-operations" will poll for due operations for the "podcast-fetch-transcript"
-- to attempt at fetching
CREATE INDEX podcast_episode_operations_fetch_results_at
    ON podcast_episode_operations (fetch_results_at);


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4734;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
