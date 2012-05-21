ALTER TABLE stories_restore ADD PRIMARY KEY( stories_id );

INSERT INTO stories_restore(
    select *from stories where stories_id > ( ( select max( stories_id ) from stories_restore ) - 100000 )
      and stories_id
      < ( select max(stories_id) from stories_restore  )  EXCEPT select * from stories_restore where stories_id >
      ( ( select max( stories_id ) from stories_restore ) - 100000 )
      and stories_id < ( select max( stories_id ) from stories_restore ) );
