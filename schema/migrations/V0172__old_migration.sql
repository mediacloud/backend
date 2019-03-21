

-- it's better to have a few duplicates than deal with locking issues, so we don't try to make this unique
create index cached_extractor_results_downloads_id on cached_extractor_results( downloads_id );

alter table cached_extractor_results alter downloads_id set not null;




