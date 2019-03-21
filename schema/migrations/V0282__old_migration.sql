


ALTER TABLE auth_users
	ADD COLUMN non_public_api BOOLEAN NOT NULL DEFAULT false;

UPDATE auth_users set non_public_api = 't';


