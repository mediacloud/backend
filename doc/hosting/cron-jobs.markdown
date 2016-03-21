Cron Jobs
=========

In addition to the daemons that run via supervisord, there are a variety of cron jobs that we use to maintain and
monitor the platform.  Below are the interesting parts of our current crontab, with comments explaining the purpose
of each job.

```
# Functional

# make sure supervisord is restarted after a reboot
@reboot /space/mediacloud/mediacloud/supervisor/supervisord.sh

# there are some extra little paranoid backup scripts.  All of this is backed up elsewhere
0 0   * * * nice /space/mediacloud/control_scripts/back_up_db_schema.sh
43 13  * * * nice /space/mediacloud/control_scripts/back_up_source_code.sh > /dev/null
0 0   * * * nice /space/mediacloud/control_scripts/back_up_scripts.sh > /dev/null

# web pages for the various controversies respond better if they have been visited recently to prime the postgres
# buffer with the relevant results.  this script just hits the main controversy tables to prime the postgres buffers.
42 * * * * /space/mediacloud/mediacloud/script/run_with_carton.sh /space/mediacloud/mediacloud/script/mediawords_cache_controversy_web.pl &> /dev/null

# we have long been plagued with a slow memory leak in the extrator system, so we restart it a couple times a day
23 4,16 * * * /space/mediacloud/control_scripts/restart_extractor_if_running.sh >& /dev/null

# we do lots of updates to the downloads and stories tables, so performance suffers if we don't vacuum the tables once
# a day (because updates are just new table writes, and reading a row requires reading all of the updated dead rows)
24 1 * * * psql -c "vacuum analyze downloads;" &> /dev/null
24 2 * * * psql -c "vacuum analyze stories;" &> /dev/null

# this is a daily script that generates health analytics for media sources in media_health
32 2 * * * /space/mediacloud/mediacloud/script/run_with_carton.sh /space/mediacloud/mediacloud/script/mediawords_generate_media_health.pl

# when we add or remove a tag to a media source, we have to reimport every story in that source to solr.  that process
# can take days and block the hourly updates, so we use this separate script to write all effected stories to the
# solr_import_extra_stories queue, and the import script (mediawords_import_solr_data.pl) pulls 100k chunks from that
# table until it is empty
11 */4 * * * /space/mediacloud/mediacloud/script/run_with_carton.sh /space/mediacloud/mediacloud/script/mediawords_queue_media_solr_exports.pl

# we use munin to monitor the process of our various system.
*/5 * * * * /space/mediacloud/munin/mediacloud-munin/munin-cron.sh &> /dev/null

# we store our raw html content on amazon s3, but we cache 3 days worth of most recently access content in the local
# file system.  This script just deletes everything older than 3 days from that cache.
0 * * * * /space/mediacloud/mediacloud/script/purge_local_s3_downloads_cache.sh

# same for bitly processing results cache
30 * * * * /space/mediacloud/mediacloud/script/purge_local_bitly_processing_results_cache.sh 35

# every ten minutes, check for stories for which to add bitly processing jobs.  we send each story to bitly for
# processing 3 and then 30 days after publication.
*/10 * * * * /space/mediacloud/mediacloud/script/run_with_carton.sh /space/mediacloud/mediacloud/script/mediawords_process_bitly_schedule.pl &> /space/mediacloud/mediacloud/data/logs/mediawords_process_bitly_schedule.log

# we rescrape every media source for new feeds every 6 months
0 3 * * *  /space/mediacloud/mediacloud/script/run_with_carton.sh /space/mediacloud/mediacloud/script/mediawords_rescrape_due_media.pl >> /space/mediacloud/mc_data/logs/rescrape_media.log 2>&1
# comment out temporarily to make dump work 0 14 * * * psql -c "SELECT rescraping_changes(); SELECT update_feeds_from_yesterday()" 2>&1

# Warning of problems

# make sure postgres is up!  this is a paranoid extra check on top of nagios monitoring
* *  *  * * psql -At -c "-- test DB UP "
0 20 * * * /space/mediacloud/vagrant_test_run/run_test.sh

# make sure that mediacloud.org is returning sane results
*/5 * * * * /space/mediacloud/monitor_scripts/web_site_check.sh http://www.mediacloud.org mediameter-dashboard

# Informational

# send us an email with the number of stories, downloads, download errors, and solr imports each day
0 6,12   * * * psql -c "select * from daily_stats "

# the next two jobs just log information about running processes and disk space that we can use to diagnose problems
* * * * * /space/mediacloud/control_scripts/print_processes.sh
34 1 * * * /space/mediacloud/control_scripts/print_disk_space.sh

# once a day, send an email with any queries that have lasted longer than a minute.  helps us spot very long queries
34 3 * * * psql -c "select pid, usename, state, query_start, query from pg_stat_activity where state not like 'idle\%' and query_start < now() - '1 minute'::interval order by query_start asc"

# the next two jobs print a summary of new user registrations and api usage for the last day and the last week
34 4 * * * /space/mediacloud/mediacloud/script/run_with_carton.sh /space/mediacloud/mediacloud/script/mediawords_generate_user_summary.pl
22 5 * * sun /space/mediacloud/mediacloud/script/run_with_carton.sh /space/mediacloud/mediacloud/script/mediawords_generate_user_summary.pl --new 7 --activity 7 | mail -s "Weekly user report" mediacloud-dev@eon.law.harvard.edu
```
