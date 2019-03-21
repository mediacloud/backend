

CREATE TABLE feedless_stories (
	stories_id integer,
	media_id integer
);


CREATE OR REPLACE FUNCTION cancel_pg_process(cancel_pid integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
return pg_cancel_backend(cancel_pid);
END;
$$;

CREATE INDEX feedless_stories_story ON feedless_stories USING btree (stories_id);

