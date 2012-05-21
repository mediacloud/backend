#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use XML::LibXML;
use Data::Dumper;

use Digest::SHA qw(sha1 sha1_hex sha1_base64);

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;
use Lingua::EN::Sentence::MediaWords;

#use XML::LibXML::Enhanced;

my $date_based_tables = {
    daily_words                => 'publish_day',
    total_daily_words          => 'publish_day',
    total_top_500_weekly_words => 'publish_week',
    total_weekly_words         => 'publish_week',
};

#story_sentence_counts

my $tables_to_save = [
    qw (
      stories
      story_sentence_words
      story_sentences
      )
];

sub get_new_table_name
{
    my ( $old_table_name, $prefix, $dates ) = @_;

    my $date_string = join '_', @{ $dates };

    $date_string =~ s/-/_/g;

    my $new_table_name = "$prefix" . "_$old_table_name" . '_' . $date_string;

    return $new_table_name;
}

sub save_table_by_stories_id
{
    my ( $dbs, $table_name, $prefix, $dates ) = @_;

    say "copying table '$table_name'";

    die if !$prefix;

    my $new_table_name = get_new_table_name( $table_name, $prefix, $dates );

    #say "DROP TABLE if exists $new_table_name ";

    $dbs->query( "DROP TABLE if exists $new_table_name " );

    $dbs->query(
" CREATE TABLE $new_table_name AS SELECT * from $table_name where stories_id in ( select stories_id from stories where date_trunc('week', publish_date) in (??) ) ",
        @{ $dates }
    );
}

sub save_table_by_date
{
    my ( $dbs, $table_name, $prefix, $dates, $date_field ) = @_;

    die unless $date_field;

    say "copying table '$table_name'";

    die if !$prefix;

    my $new_table_name = get_new_table_name( $table_name, $prefix, $dates );

    #say "DROP TABLE if exists $new_table_name ";

    $dbs->query( "DROP TABLE if exists $new_table_name " );

    my $date_list = join ",", map { "'$_'" } @{ $dates };

    my $sql = " CREATE TABLE $new_table_name AS SELECT * from $table_name where $date_field in ( $date_list ) ;";

    say $sql;

    $dbs->query( $sql );
}

# do a test run of the text extractor
sub main
{

    my $dbs = MediaWords::DB::connect_to_db;

    my $dates = [ '2011-01-03', '2011-01-10' ];

    my $prefix = 'sen_study_new';

    #my $prefix = 'sen_study_old';

    foreach my $date_based_table ( sort keys %{ $date_based_tables } )
    {
        save_table_by_date( $dbs, $date_based_table, $prefix, $dates, $date_based_tables->{ $date_based_table } );
    }

    foreach my $table_to_save ( @$tables_to_save )
    {
        save_table_by_stories_id( $dbs, $table_to_save, $prefix, $dates );
    }

    exit;

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'      => \$file,
        'downloads|d=s' => \@download_ids,
    ) or die;

    unless ( $file || ( @download_ids ) )
    {
        die "no options given ";
    }

}

main();
