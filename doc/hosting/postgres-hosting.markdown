Postgres Notes
==============

Following are helpful notes for dealing with our local postgres setup.

PPS
---

I am constantly calling a local script I created as '/bin/pps' (for 'postgres ps') that is defined as:

```
#!/bin/sh
echo "select pid, usename, state, query_start, substr(  regexp_replace(query, E'[\\n\\r ]+', ' ', 'g' ), 0, 140 ) q from pg_stat_activity where state not like 'idle%' order by query_start desc" | psql med
iacloud
```

This gives output that looks like this:

```
hroberts@mcdb1:~$ pps
  pid  |  usename   | state  |          query_start          |                                                                      q
-------+------------+--------+-------------------------------+---------------------------------------------------------------------------------------------------------------------------------------------
 12612 | mediacloud | active | 2016-03-15 11:00:41.371201-04 | select * from stories where stories_id = $1
 39814 | mediacloud | active | 2016-03-15 11:00:41.368527-04 | select pid, usename, state, query_start, substr( regexp_replace(query, E'[\n\r ]+', ' ', 'g' ), 0, 140 ) q from pg_stat_activity where stat
 39330 | mediacloud | active | 2016-03-15 11:00:41.364449-04 |  WITH reextract_stories as (select ps.* from processed_stories ps left join stories_tags_map stm on ( ps.stories_id=stm.stories_id and stm.
 13517 | mediacloud | active | 2016-03-15 10:59:04.106124-04 | create temporary table dump_story_link_counts as select distinct ps.stories_id, coalesce( ilc.inlink_count, 0 ) inlink_count, coalesce( olc
 ```

 I also have a '/bin/ppsl' (for 'pps long') that does not cut off each query at 140 characters:

 ```
 #!/bin/sh
echo "select pid, usename, state, query_start, query from pg_stat_activity where state not like 'idle%' order by query_start desc" | psql mediacloud
```

cancel_pg_process()
-------------------

We have defined a function that runs with postgres superuser privileges that cancels any running postgres query.  So if
want to cancel the last query above, you run:

```
select cancel_pg_process( 13517 );
```

Blocking Queries
----------------

We try to avoid long transactions and locking wherever humanly possible in the codebase to avoid difficult to diagnose
blocking problems.  But we have a couple of views defined for cases in which you suspect blocking:

* blocking_tree - a query that returns in tree form blocked and blocking queries
* blocked_queries - a simple list of all queries that are currently blocked by some lock

For reasons that I don't understand, one of these queries will very occasionally returned blocked queries missed by
the other.

Object Size
-----------

Here's a query to return the size in GB of all objects in the database:

```
select p.relname, ( p.relpages * 8 ) / ( 1024 * 1024 ) from pg_class p order by p.relpages desc;
```

Here's a similar query for just indexes, which also displays read stats on each index (useful for finding big indexes
that we are not using):

```
SELECT p.relname, ( p.relpages * 8 ) / ( 1024 * 1024 ), i.idx_scan, i.idx_tup_read, i.idx_tup_fetch  FROM pg_class p, pg_stat_user_indexes i where i.indexrelname = p.relname ORDER BY relpages DESC;
```

postgres.conf
-------------

As of 20160315, here are the interesting parts of our postgresql.conf:

```
port = 5432				# (change requires restart)
max_connections = 300			# (change requires restart)
unix_socket_directories = '/var/run/postgresql'	# comma-separated list of directories
shared_buffers = 64GB			# min 128kB
temp_buffers = 128MB			# min 800kB
work_mem = 256MB				# min 64kB
maintenance_work_mem = 256MB		# min 1MB
vacuum_cost_delay = 0			# 0-100 milliseconds
vacuum_cost_limit = 10000		# 1-10000 credits
effective_io_concurrency = 20		# 1-1000; 0 disables prefetching
hot_standby = on			# "on" allows queries during recovery
hot_standby_feedback = on		# send info from standby to prevent
random_page_cost = 1.0			# same scale as above
effective_cache_size = 64GB
log_line_prefix = '%t [%p-%l] %q%u@%d '			# special values:
log_lock_waits = on			# log lock waits >= deadlock_timeout
log_timezone = 'localtime'
autovacuum_vacuum_cost_delay = 	-1	# default vacuum cost delay for
autovacuum_vacuum_cost_limit = -1	# default vacuum cost limit for
datestyle = 'iso, mdy'
timezone = 'localtime'
lc_messages = 'en_US.UTF-8'			# locale for system error message
lc_monetary = 'en_US.UTF-8'			# locale for monetary formatting
lc_numeric = 'en_US.UTF-8'			# locale for number formatting
lc_time = 'en_US.UTF-8'				# locale for time formatting
default_text_search_config = 'pg_catalog.english'
```
