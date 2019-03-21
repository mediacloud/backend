

DROP INDEX auth_users_tag_sets_permissions_auth_user;

DROP INDEX auth_users_tag_sets_permissions_tag_sets;


CREATE INDEX auth_users_tag_sets_permissions_auth_user ON auth_users_tag_sets_permissions ( auth_users_id );

CREATE INDEX auth_users_tag_sets_permissions_tag_sets ON auth_users_tag_sets_permissions ( tag_sets_id );

