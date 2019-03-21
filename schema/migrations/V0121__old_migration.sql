

-- log of all stories import into solr, with the import date
create table solr_imported_stories (
    stories_id          int not null references stories on delete cascade,
    import_date         timestamp not null
);

create index solr_imported_stories_story on solr_imported_stories ( stories_id );
create index solr_imported_stories_day on solr_imported_stories ( date_trunc( 'day', import_date ) );



