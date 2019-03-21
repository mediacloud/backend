


-- Generate random API token
CREATE OR REPLACE FUNCTION generate_api_token() RETURNS VARCHAR(64) LANGUAGE plpgsql AS $$
DECLARE
    token VARCHAR(64);
BEGIN
    SELECT encode(digest(gen_random_bytes(256), 'sha256'), 'hex') INTO token;
    RETURN token;
END;
$$;

-- Add "api_token" column (API tokens will be generated for old users)
ALTER TABLE auth_users
	ADD COLUMN api_token VARCHAR(64)     UNIQUE NOT NULL DEFAULT generate_api_token() CONSTRAINT api_token_64_characters CHECK(LENGTH(api_token) = 64);

--
-- Incorporate changes from the 4430->4431 diff from master
--

ALTER TYPE download_state ADD value 'extractor_error';

-- Fix downloads marked as errors when the problem was with the extractor
UPDATE downloads set state = 'extractor_error' where state='error' and type='content' and error_message is not null and error_message like 'extractor_error%';



