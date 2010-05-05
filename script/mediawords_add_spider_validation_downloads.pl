#!/usr/bin/perl -w

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use MediaWords::DB;
use DBIx::Simple::MediaWords;

#use MediaWords::DBI::Found_BlogsTagsMapMediaSubtables;
use TableCreationUtils;
use Readonly;
use Term::Prompt;
use URI::Split;
use Data::Dumper;
use Carp;

my $_found_blogs_id_start       = 0000000;
my $_found_blogs_id_window_size = 10000;
my $_found_blogs_id_stop        = $_found_blogs_id_start + $_found_blogs_id_window_size;
my $_cached_max_found_blogs_id  = 0;

sub get_max_found_blogs_id
{
    my ($dbh) = @_;

    my $max_found_blogs_id_row = $dbh->query("select max(found_blogs_id) as max_id from found_blogs");

    my $max_found_blogs_id = $max_found_blogs_id_row->hash()->{max_id};

    $_cached_max_found_blogs_id = $max_found_blogs_id;

    return $max_found_blogs_id;
}

sub scroll_found_blogs_id_window
{
    $_found_blogs_id_start = $_found_blogs_id_stop;
    $_found_blogs_id_stop  = $_found_blogs_id_start + $_found_blogs_id_window_size;

    print STDERR "story_id windows: $_found_blogs_id_start -- $_found_blogs_id_stop   (max_found_blogs_id: "
      . $_cached_max_found_blogs_id
      . ")  -- "
      . localtime() . "\n";
}

sub get_rows_in_found_blogs_id_window
{
    my ($dbh) = @_;

    print STDERR "starting fetching rows in window $_found_blogs_id_start - $_found_blogs_id_stop  ... -- "
      . localtime() . "\n";

    my $rows =
      $dbh->query( "select * from found_blogs where found_blogs.found_blogs_id < ? and found_blogs.found_blogs_id >= ? ",
        $_found_blogs_id_stop, $_found_blogs_id_start );

    print STDERR "finished fetching rows in window ... -- " . localtime() . "\n";

    return $rows;
}

my @_existing_media_sub_tables;

sub exists_media_id_sub_table
{
    my ($media_id) = @_;

    if ( defined( $_existing_media_sub_tables[$media_id] ) )
    {
        return 1;
    }

    return 0;
}

sub isNonnegativeInteger
{
    my ($val) = @_;

    return int($val) eq $val;
}

sub insert_validation_download
{
    ( my $dbh, my $found_blogs_id, my $url, my $downloads_type ) = @_;

    my $inserted_download;

    $inserted_download = $dbh->insert(
        'downloads',
        {
            url           => $url,
            host          => lc( ( URI::Split::uri_split( $url ) )[1] ),
            type          => $downloads_type,
            sequence      => 0,
            state         => 'pending',
            priority      => 0,
            download_time => 'now()',
        }
    );

    my $id = $dbh->last_insert_id( undef, undef, 'downloads', undef );

    confess "Could not get last id inserted" if ( !defined($id) );

    #print Dumper($id);

    $dbh->insert(
        'blog_validation_downloads',
        {
            found_blogs_id => $found_blogs_id,
            downloads_id   => $id,
            downloads_type => $downloads_type
        }
    ) or confess "";
}

sub main
{
    my $result = &prompt( "y", "Are you sure you wish to continue?", "", "n" );

    exit unless ($result);

    my $dbh = TableCreationUtils::get_database_handle();

    my $max_found_blogs_id = get_max_found_blogs_id($dbh);

    while ( $_found_blogs_id_start <= $max_found_blogs_id )
    {
        my $rows_to_insert = get_rows_in_found_blogs_id_window($dbh);

        my $rows_fetched_in_batch = 0;

        #$dbh->begin_work;
        while ( my $found_blog_hash = $rows_to_insert->hash )
        {
            $rows_fetched_in_batch++;
            insert_validation_download(
                $dbh,
                $found_blog_hash->{found_blogs_id},
                $found_blog_hash->{url},
                'spider_validation_blog_home'
            );
            insert_validation_download(
                $dbh,
                $found_blog_hash->{found_blogs_id},
                $found_blog_hash->{rss},
                'spider_validation_rss'
            );
        }

        #$dbh->commit;

        scroll_found_blogs_id_window();
    }

    $dbh->disconnect;
}

main();
