

ALTER TABLE database_variables
	RENAME COLUMN variables_id to database_variables_id;

ALTER SEQUENCE database_variables_variables_id_seq RENAME TO database_variables_datebase_variables_id_seq;



