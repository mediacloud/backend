#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Readonly;

#use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
#
use Data::Dumper;

# do a test run of the text extractor
sub main
{
    my $dbs = MediaWords::DB::connect_to_db();

    $dbs->query('select setseed(.12345);');

    my $table_names_query = "SELECT table_name FROM information_schema.tables WHERE table_type <> 'VIEW' and table_schema = 'public' and not ( table_name like 'sopa_date_counts_dump_00%' ) and not ( table_name like 'sopa_links_dump_00%'  ) and not ( table_name like 'sopa_media_dump%' ) and not ( table_name like 'sopa_%' ) order by table_name asc";

    my @tables = $dbs->query( $table_names_query )->flat();

    my @non_id_tables = qw ( daily_country_counts daily_stats daily_words_with_totals india_million media_tag_counts queries_dashboard_topics_map queries_media_sets_map ssw_queue story_sentence_words tar_downloads_queue top_ten_tags_for_media url_discovery_counts extractor_training_lines_corrupted_download_content hr_pilot_study_stories ma_ms_queue media_rss_full_text_detection_data original_sopa_story_publish_dates pilot_story_sims pilot_story_sims_code pilot_study_stories questionable_downloads_rows sopa_58b_sentiment sopa_date_counts_dump sopa_date_counts_dump_000004 sopa_date_counts_dump_000005 sopa_date_counts_dump_000006 sopa_date_counts_dump_000007 sopa_date_counts_dump_000008 sopa_date_counts_dump_000009 sopa_date_counts_dump_000011 sopa_date_counts_dump_000012 sopa_date_counts_dump_000021 sopa_date_counts_dump_000022 sopa_date_counts_dump_000023 sopa_date_counts_dump_000024 sopa_links_20120224 sopa_links_20120225 sopa_links_20120302 sopa_links_copy sopa_links_dump   sopa_links_pre_december_spidered sopa_links_pre_google sopa_links_pre_reboot sopa_links_with_acta sopa_media_58b_sentiment sopa_media_dump sopa_media_links_dump stories_description_not_salvaged total_daily_media_words);

    @tables = get_complement( [ \@non_id_tables, \@tables ] );

    my @web_writtable_tables = qw ( query_story_searches media_tags_map popular_queries queries queries_country_counts_json queries_top_weekly_words_json
 query_story_searches );

    @tables = get_complement( [ \@web_writtable_tables, \@tables ] );

    say "Dumping tables";

    say Dumper( \@tables );

    foreach my $table ( @tables )
    {
	say "Dumping min max of table $table";

	my $min_max_query = "select min($table" . "_id) as min, max($table" . "_id) from $table";

	
	say Dumper( $dbs->query( $min_max_query )->hashes );

	#say "Dumping sample of table '$table'";
	my $query = "select * from $table where $table" . "_id in (select floor(random() * (max_id - min_id + 1))::integer + min_id " .
	    " from generate_series(1,15), (select max($table" . "_id) as max_id, min($table" . "_id) as min_id from $table) s1 " .
	    "        limit 15)  order by random() limit 5; ";

	#say Dumper( $dbs->query($query)->hashes );
    }
}

main();
