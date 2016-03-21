#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use Modern::Perl "2015";

# basic sanity test of crawler functionality

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More tests => 2;
use Test::Differences;
use Test::Deep;

require Test::NoWarnings;

use MediaWords::Crawler::Engine;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::MediaSets;
use MediaWords::DBI::Stories;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use DBIx::Simple::MediaWords;
use MediaWords::StoryVectors;
use LWP::UserAgent;

use Data::Sorting qw( :basics :arrays :extras );
use Readonly;

#use feature 'unicode_strings';

sub test_query_with_large_work_mem
{
    my ( $db, $feed ) = @_;

    $db->query_with_large_work_mem( " SELECT 'foo' FROM DOWNLOADS where downloads_id > ? LIMIT 1 ", 0 )->flat;

    ( my $result ) = $db->query_with_large_work_mem( " SELECT 'foo' " )->flat;

    is( $result, 'foo' );
}

sub main
{

    my ( $dump ) = @ARGV;

    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            test_query_with_large_work_mem( $db );

            Test::NoWarnings::had_no_warnings();
        }
    );

}

main();

