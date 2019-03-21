
create table color_sets (
    color_sets_id               serial          primary key,
    color                       varchar( 256 )  not null,
    color_set                   varchar( 256 )  not null,
    id                          varchar( 256 )  not null
);
  
create index color_sets_set_id on color_sets ( color_set, id );
    
-- prefill colors for partisan_code set so that liberal is blue and conservative is red
insert into color_sets ( color, color_set, id ) values ( 'c10032', 'partisan_code', 'partisan_2012_conservative' );
insert into color_sets ( color, color_set, id ) values ( '00519b', 'partisan_code', 'partisan_2012_liberal' );
insert into color_sets ( color, color_set, id ) values ( '009543', 'partisan_code', 'partisan_2012_libertarian' );




