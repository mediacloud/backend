

alter table controversies add controversy_tag_sets_id int references tag_sets;

update controversies c set controversy_tag_sets_id = ts.tag_sets_id
    from tag_sets ts
    where ts.name = 'controversy_' || c.name;
    
alter table controversies alter controversy_tag_sets_id set not null;

alter table controversies add media_type_tag_sets_id int references tag_sets;

create unique index controversies_tag_set on controversies( controversy_tag_sets_id );
create unique index controversies_media_type_tag_set on controversies( media_type_tag_sets_id );





