



ALTER TABLE gearman_job_queue
	-- Unique Gearman job identifier that describes the job that is being run.
    --
    -- In the Gearman::JobScheduler's case, this is a SHA256 of the serialized
    -- Gearman function name and its parameters, e.g.
    --
    --     sha256_hex("MediaWords::GearmanFunction::CM::DumpControversy({controversies_id => 1})")
    --     =
    --     "b9758abbd3811b0aaa53d0e97e188fcac54f58a876bb409b7395621411401ee8"
    --
    -- Although "job_handle" above also serves as an unique identifier of the
    -- specific job, and Gearman uses both at the same time to identify a job,
    -- it provides no way to fetch the "unique job ID" (e.g. this SHA256 string)
    -- by having a Gearman job handle (e.g. "H:tundra.local:8") and vice versa,
    -- so we have to store it somewhere ourselves.
    --
    -- The "unique job ID" is needed to check if the job with specific
    -- parameters (e.g. a "dump controversy" job for the controversy ID) is
    -- enqueued / running / failed.
    --
    -- The unique job ID's length is limited to Gearman internal
    -- GEARMAN_MAX_UNIQUE_SIZE which is set to 64 at the time of writing.
	ADD COLUMN unique_job_id VARCHAR(64) NOT NULL;

CREATE INDEX gearman_job_queue_unique_job_id ON gearman_job_queue (unique_job_id);




