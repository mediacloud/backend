#!/usr/bin/env perl

# query a random set of feeds and generate a list of feedly stories that would be added to media cloud if we were to run
# a feedly import for that feed

# usage: $0 < num_feeds >

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use Encode;

use MediaWords::DB;
use MediaWords::ImportStories::Feedly;
use MediaWords::Util::CSV;
use MediaWords::Util::SQL;

sub get_date_range
{
    my ( $new_stories ) = @_;

    $new_stories = [ sort { $a->{ publish_date } cmp $b->{ publish_date } } @{ $new_stories } ];

    my $earliest_story = $new_stories->[ 0 ];
    my $latest_story   = pop( @{ $new_stories } );

    return ( $earliest_story->{ publish_date }, $latest_story->{ publish_date } );
}

sub main
{
    my ( $num_media ) = @ARGV;

    die( "usage: $0 <num_media>" ) unless ( $num_media );

    my $db = MediaWords::DB::connect_to_db;

    my $media = $db->query( <<SQL, $num_media )->hashes;
select *
    from media
    where media_id in ( select media_id from feeds where feed_status = 'active' )
    order by random()
    limit ? * 2
SQL

    my $dates = [];

    my $validate_stories = [];

    my $media_data = [];

    my $total_num_media        = 0;
    my $total_imported_stories = 0;
    my $overall_start_date     = MediaWords::Util::SQL::get_sql_date_from_epoch( time() );

    my $scraped_media = [];
    for my $medium ( @{ $media } )
    {
        $total_num_media++;

        my $feeds = $db->query( "select * from feeds where media_id = ?", $medium->{ media_id } )->hashes;
        my $feed_urls = [ map { $_->{ url } } @{ $feeds } ];

        say STDERR "medium: " . scalar( @{ $scraped_media } ) . " / $num_media";

        my $import = MediaWords::ImportStories::Feedly->new(
            db       => $db,
            media_id => $medium->{ media_id },
            dry_run  => 1,
            feed_url => $feed_urls
        );

        my $import_stories;

        eval { $import_stories = $import->scrape_stories(); };
        warn( $@ ) if ( $@ );

        $total_imported_stories += scalar( @{ $import_stories } );

        my $new_stories = $import->module_stories();

        next unless ( $new_stories && @{ $new_stories } );

        my $import_stories_lookup = {};
        map { $import_stories_lookup->{ $_->{ guid } } = 1 } @{ $import_stories };

        map { $_->{ import } = $import_stories_lookup->{ $_->{ guid } } || 0 } @{ $new_stories };

        map { $_->{ _r } = rand() } @{ $new_stories };

        my ( $start_date, $end_date ) = get_date_range( $new_stories );

        say STDERR "date range: $start_date - $end_date";
        $overall_start_date = ( $start_date lt $overall_start_date ) ? $start_date : $overall_start_date;

        splice( @{ $new_stories }, 10 );

        for my $new_story ( @{ $new_stories } )
        {
            $new_story->{ dup_stories_id } ||= 0;
            delete( $new_story->{ _r } );
            delete( $new_story->{ description } );
        }

        push( @{ $validate_stories }, @{ $new_stories } );

        $medium->{ feedly_start_date }     = $start_date;
        $medium->{ feedly_end_date }       = $end_date;
        $medium->{ feedly_stories }        = scalar( @{ $new_stories } );
        $medium->{ feedly_import_stories } = scalar( @{ $import_stories } );

        push( @{ $scraped_media }, $medium );

        last if ( scalar( @{ $scraped_media } ) >= $num_media );
    }

    # binmode( STDOUT, 'utf8' );
    #
    # map { say $_->{ title }; } @{ $validate_stories };

    print( MediaWords::Util::CSV::get_hashes_as_encoded_csv( $validate_stories ) );
    print( MediaWords::Util::CSV::get_hashes_as_encoded_csv( $scraped_media ) );

    say STDERR "total media tried: $total_num_media";
    say STDERR "num media with feedly stories: " . scalar( @{ $scraped_media } );
    say STDERR "num imported stories: $total_imported_stories";
    say STDERR "earliest story: $overall_start_date";
}

main();
