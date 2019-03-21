


CREATE TABLE auth_users_subscribe_to_newsletter (
    auth_users_subscribe_to_newsletter_id SERIAL  PRIMARY KEY,
    auth_users_id                         INTEGER NOT NULL REFERENCES auth_users (auth_users_id) ON DELETE CASCADE
);



