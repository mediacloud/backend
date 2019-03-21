

alter table feeds add skip_bitly_processing boolean;

update feeds set skip_bitly_processing = true where name like 'MediaWords::ImportStories%';



