#!/bin/sh

psql -c "select  setseed (12345); select * from (select distinct(host) from non_blog_host_links order by host) as foo order by random() limit 100;"
 