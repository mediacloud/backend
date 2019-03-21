

drop index stories_title_pubdate;

create index stories_title_hash on stories( md5( title ) );




