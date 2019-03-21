

CREATE TABLE auth_users_tag_sets_permissions (
	auth_users_tag_sets_permissions_id SERIAL  PRIMARY KEY,
	auth_users_id integer references auth_users NOT NULL,
	tag_sets_id integer references tag_sets NOT NULL,
	apply_tags boolean NOT NULL,
	create_tags boolean NOT NULL,
	edit_tag_set_descriptors boolean NOT NULL,
	edit_tag_descriptors boolean NOT NULL
);


CREATE UNIQUE INDEX auth_users_tag_sets_permissions_auth_user_tag_set ON auth_users_tag_sets_permissions ( auth_users_id , tag_sets_id );

CREATE UNIQUE INDEX auth_users_tag_sets_permissions_auth_user ON auth_users_tag_sets_permissions ( auth_users_id );

CREATE UNIQUE INDEX auth_users_tag_sets_permissions_tag_sets ON auth_users_tag_sets_permissions ( tag_sets_id );

