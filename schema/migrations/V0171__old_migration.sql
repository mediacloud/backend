


-- Returns first 64 bits (16 characters) of MD5 hash
--
-- Useful for reducing index sizes (e.g. in story_sentences.sentence) where
-- 64 bits of entropy is enough.
CREATE OR REPLACE FUNCTION half_md5(string TEXT) RETURNS bytea AS $$
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT SUBSTRING(public.digest(string, 'md5'::text), 0, 9);
$$ LANGUAGE SQL;


-- Generate random API key
CREATE OR REPLACE FUNCTION generate_api_key() RETURNS VARCHAR(64) LANGUAGE plpgsql AS $$
DECLARE
    api_key VARCHAR(64);
BEGIN
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT encode(public.digest(public.gen_random_bytes(256), 'sha256'), 'hex') INTO api_key;
    RETURN api_key;
END;
$$;



