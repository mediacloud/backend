-- Returns first 64 bits (16 characters) of MD5 hash
--
-- Useful for reducing index sizes (e.g. in story_sentences.sentence) where
-- 64 bits of entropy is enough.
CREATE OR REPLACE FUNCTION half_md5(string TEXT) RETURNS bytea AS $$
    SELECT SUBSTRING(digest(string, 'md5'::text), 0, 9);
$$ LANGUAGE SQL;


