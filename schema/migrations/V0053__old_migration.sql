

create view controversy_links_cross_media as
  select s.stories_id, sm.name as media_name, r.stories_id as ref_stories_id, rm.name as ref_media_name, cl.url as url, cs.controversies_id, cl.controversy_links_id from media sm, media rm, controversy_links cl, stories s, stories r, controversy_stories cs where cl.ref_stories_id <> cl.stories_id and s.stories_id = cl.stories_id and cl.ref_stories_id = r.stories_id and s.media_id <> r.media_id and sm.media_id = s.media_id and rm.media_id = r.media_id and cs.stories_id = cl.ref_stories_id and cs.controversies_id = cl.controversies_id;

