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

    my $table_names_query = "SELECT table_name FROM information_schema.tables WHERE table_type <> 'VIEW' and table_schema = 'public' order by table_name asc";

    my @tables = $dbs->query( $table_names_query )->flat();

    my @non_id_tables = qw ( daily_country_counts daily_stats daily_words_with_totals india_million media_tag_counts queries_dashboard_topics_map queries_media_sets_map ssw_queue story_sentence_words tar_downloads_queue top_ten_tags_for_media url_discovery_counts extractor_training_lines_corrupted_download_content hr_pilot_study_stories ma_ms_queue);

    @tables = get_complement( [ \@non_id_tables, \@tables ] );

    foreach my $table ( @tables )
    {
	say "Dumping sample of table '$table'";
	my $query = "select * from $table where $table" . "_id in (select floor(random() * (max_id - min_id + 1))::integer + min_id " .
	    " from generate_series(1,15), (select max($table" . "_id) as max_id, min($table" . "_id) as min_id from $table) s1 " .
	    "        limit 15)  order by random() limit 5; ";

	say Dumper( $dbs->query($query)->hashes );
    }
}

main();
