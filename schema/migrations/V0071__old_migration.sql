



--
-- Gearman job queue (jobs enqueued with enqueue_on_gearman())
--

CREATE TYPE gearman_job_queue_status AS ENUM (
    'enqueued',     -- Job is enqueued and waiting to be run
    'running',      -- Job is currently running
    'finished',     -- Job has finished successfully
    'failed'        -- Job has failed
);

CREATE TABLE gearman_job_queue (
    gearman_job_queue_id    SERIAL                      PRIMARY KEY,

    -- Last status update time
    last_modified           TIMESTAMP                   NOT NULL DEFAULT LOCALTIMESTAMP,

    -- Gearman function name (e.g. "MediaWords::GearmanFunction::CM::DumpControversy")
    function_name           VARCHAR(255)                NOT NULL,

    -- Gearman job handle (e.g. "H:tundra.local:8")
    --
    -- This table expects all job handles to be unique, and Gearman would not
    -- generate unique job handles if it is configured to store the job queue
    -- in memory (as it does by default), so you *must* configure a persistent
    -- queue storage.
    -- For an instruction on how to store the Gearman job queue on PostgreSQL,
    -- see doc/README.gearman.markdown.
    job_handle              VARCHAR(255)                UNIQUE NOT NULL,

    -- Job status
    status                  gearman_job_queue_status    NOT NULL,

    -- Error message (if any)
    error_message           TEXT                        NULL
);

CREATE INDEX gearman_job_queue_function_name ON gearman_job_queue (function_name);
CREATE UNIQUE INDEX gearman_job_queue_job_handle ON gearman_job_queue (job_handle);
CREATE INDEX gearman_job_queue_status ON gearman_job_queue (status);

-- Update "last_modified" on UPDATEs
CREATE FUNCTION gearman_job_queue_sync_lastmod() RETURNS trigger AS $$
BEGIN
    NEW.last_modified := NOW();
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER gearman_job_queue_sync_lastmod
    BEFORE UPDATE ON gearman_job_queue
    FOR EACH ROW EXECUTE PROCEDURE gearman_job_queue_sync_lastmod();





