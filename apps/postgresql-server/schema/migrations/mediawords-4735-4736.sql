--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4735 and 4736.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4735, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4736, import this SQL file:
--
--     psql mediacloud < mediawords-4735-4736.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


ALTER TYPE feed_type ADD VALUE 'podcast';


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

    -- Enclosure that's considered to point to a podcast episode
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
                                            ),

    -- Speech API operation ID to be used for retrieving transcription; if NULL,
    -- transcription job hasn't been submitted yet
    speech_operation_id     TEXT        NULL

);

-- Only one episode per story
CREATE UNIQUE INDEX podcast_episodes_stories_id
    ON podcast_episodes (stories_id);

CREATE UNIQUE INDEX podcast_episodes_story_enclosures_id
    ON podcast_episodes (story_enclosures_id);

CREATE UNIQUE INDEX podcast_episodes_stories_id_story_enclosures_id
    ON podcast_episodes (stories_id, story_enclosures_id);


-- Result of an attempt to fetch the transcript
CREATE TYPE podcast_episode_transcript_fetch_result AS ENUM (

    -- Operation was not yet finished yet at the time of fetching
    'in_progress',

    -- Operation was finished and transcription has succeeded
    'success',

    -- Operation was finished but the transcription has failed
    'error'

);


--
-- Attempts to fetch podcast episode transcript
-- (we might need to try fetching the operation's results multiple times)
--
CREATE TABLE podcast_episode_transcript_fetches (
    podcast_episode_transcript_fetches_id   BIGSERIAL   PRIMARY KEY,

    -- Podcast that is being transcribed
    podcast_episodes_id     BIGINT  NOT NULL
                                        REFERENCES podcast_episodes (podcast_episodes_id)
                                        ON DELETE CASCADE,

    -- Timestamp for when a fetch job should be added to the job broker's queue the soonest
    add_to_queue_at     TIMESTAMP WITH TIME ZONE                NOT NULL,

    -- Timestamp for when a fetch job was added to the job broker's queue;
    -- if NULL, a fetch job was never added to the queue
    added_to_queue_at   TIMESTAMP WITH TIME ZONE                NULL,

    -- Timestamp when the operation's results were attempted to be fetched by the worker;
    -- if NULL, the results weren't attempted to be fetched yet
    fetched_at      TIMESTAMP WITH TIME ZONE                    NULL,

    -- Result of the fetch attempt;
    -- if NULL, the operation fetch didn't happen yet
    result          podcast_episode_transcript_fetch_result     NULL,

    -- If result = 'error', error message that happened with the fetch attempt
    error_message   TEXT                                        NULL

);


-- Function that returns true if results were attempted at being fetched
CREATE FUNCTION podcast_episode_transcript_was_added_to_queue(p_added_to_queue_at TIMESTAMP WITH TIME ZONE)
RETURNS BOOL AS $$

    SELECT CASE WHEN p_added_to_queue_at::timestamp IS NULL THEN false ELSE true END;

$$ LANGUAGE SQL IMMUTABLE;


CREATE INDEX podcast_episode_transcript_fetches_podcast_episodes_id
    ON podcast_episode_transcript_fetches (podcast_episodes_id);

CREATE UNIQUE INDEX podcast_episode_transcript_fetches_due
    ON podcast_episode_transcript_fetches (
        add_to_queue_at,
        podcast_episode_transcript_was_added_to_queue(added_to_queue_at)
    );


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4736;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
