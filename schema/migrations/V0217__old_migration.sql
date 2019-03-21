


ALTER FUNCTION generate_api_token()
    RENAME TO generate_api_key;

ALTER INDEX auth_users_token
    RENAME TO auth_users_api_key;

ALTER INDEX auth_user_ip_tokens_token
    RENAME TO auth_user_ip_tokens_api_key_ip_address;

ALTER TABLE auth_users
    RENAME COLUMN api_token TO api_key;

ALTER TABLE auth_user_ip_tokens
    RENAME TO auth_user_ip_address_api_keys;

ALTER TABLE auth_user_ip_address_api_keys
    RENAME COLUMN auth_user_ip_tokens_id TO auth_user_ip_address_api_keys_id;
ALTER TABLE auth_user_ip_address_api_keys
    RENAME COLUMN api_token TO api_key;

ALTER INDEX auth_user_ip_tokens_api_key_ip_address
    RENAME TO auth_user_ip_address_api_keys_api_key_ip_address;


