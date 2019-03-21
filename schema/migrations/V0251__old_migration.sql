

ALTER INDEX auth_users_roles_map_users_id_roles_id
	RENAME TO auth_users_roles_map_auth_users_id_auth_roles_id;

ALTER TABLE auth_users
	RENAME users_id TO auth_users_id;

ALTER TABLE auth_roles
	RENAME roles_id TO auth_roles_id;

ALTER TABLE auth_users_roles_map
	RENAME auth_users_roles_map TO auth_users_roles_map_id;
ALTER TABLE auth_users_roles_map
	RENAME users_id TO auth_users_id;
ALTER TABLE auth_users_roles_map
	RENAME roles_id TO auth_roles_id;



