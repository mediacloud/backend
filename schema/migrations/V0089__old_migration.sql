

create index tags_fts on tags using gin(to_tsvector('english'::regconfig, (tag::text || ' '::text) || label::text));

drop index tags_tag_1;
drop index tags_tag_2;
drop index tags_tag_3;



