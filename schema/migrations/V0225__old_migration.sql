
create table solr_imports (
    solr_imports_id     serial primary key,
    import_date         timestamp not null,
    full_import         boolean not null default false
);

create index solr_imports_date on solr_imports ( import_date );




