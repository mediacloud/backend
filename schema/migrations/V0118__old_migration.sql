

alter table media add last_solr_import_date timestamp with time zone not null default now();

update media set last_solr_import_date = dv.value::timestamp from database_variables dv where dv.name = 'last_media_solr_import';



