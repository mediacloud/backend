#!/usr/bin/env perl

# add a story for every story in the wapo archives here:
#

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Date::Format;
use Encode;

use MediaWords::DB;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;

use constant WAPO_MEDIA_ID => 2;
use constant START_DATE    => '2012-09-01';
use constant END_DATE      => '2012-09-02';

#use constant END_DATE => '2013-06-01';

# get teh content for the archvie page for the given date
sub get_archive_page_content
{
    my ( $date ) = @_;

    my $url_date = Date::Format::time2str( "%Y/%b/%d", MediaWords::Util::SQL::get_epoch_from_sql_date( $date ) );

    my $html = MediaWords::Util::Web::get_decoded_content( "http://articles.washingtonpost.com/$url_date" );

    die( "Unable to fetch html for date $url_date" ) unless ( $html );

    return $html;
}

# import a story with the given url, title, and date into the given medium and feed
# if it does not already exist
sub import_story
{
    my ( $db, $url, $title, $date, $medium, $feed ) = @_;

    my $existing_story = $db->query( <<'END', $medium->{ media_id }, $title, $url )->hash;
select *
    from stories
    where
        media_id = $1 and
        ( ( lower( title ) = lower( $2 ) ) or
          ( url = $3 ) or
          ( guid = $3 ) )
END
    if ( $existing_story )
    {
        print STDERR "exising story\n";
        return;
    }

    my $story = {
        url          => encode( 'utf8', $url ),
        guid         => encode( 'utf8', $url ),
        media_id     => $medium->{ media_id },
        collect_date => DateTime->now->datetime,
        title        => encode( 'utf8', $title ),
        description  => '',
        publish_date => $date,
    };

    eval { $story = $db->create( 'stories', $story ) };
    carp( $@ . " - " . Dumper( $story ) ) if ( $@ );

    print STDERR "add story: $story->{ title } / $story->{ url } / $story->{ publish_date } / $story->{ stories_id }\n";

    $db->create( 'feeds_stories_map', { feeds_id => $feed->{ feeds_id }, stories_id => $story->{ stories_id } } );

    my $host = lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] );

    my $download = {
        feeds_id      => $feed->{ feeds_id },
        stories_id    => $story->{ stories_id },
        url           => encode( 'utf8', $story->{ url } ),
        host          => encode( 'utf8', $host ),
        type          => 'content',
        sequence      => 1,
        state         => 'success',
        path          => 'content:pending',
        priority      => 1,
        download_time => DateTime->now->datetime,
        extracted     => 't'
    };

    $download = $db->create( 'downloads', $download );

    my $content = MediaWords::Util::Web::get_decoded_content( $url );

    if ( $content )
    {
        MediaWords::DBI::Downloads::store_content( $db, $download, \$content );
        extract_download( $db, $download );
    }
    else
    {
        print STDERR "no content for url '$url'\n";
    }

    return $story;
}

# import all of the stories for the given date
sub import_date
{
    my ( $db, $date, $medium, $feed ) = @_;

    my $html = get_archive_page_content( $date );

    while ( $html =~ m~<li><h3><a title=\"([^\"]*)\"\s+href=\"([^\"]*)\">~gsm )
    {
        my ( $title, $url ) = ( $1, $2 );
        print STDERR "$date: '$url' '$title'\n";
        import_story( $db, $url, $title, $date, $medium, $feed );
    }
}

# get media source and feed for imported stories
sub get_wapo_medium_and_feed
{
    my ( $db ) = @_;

    my $medium = $db->find_by_id( 'media', WAPO_MEDIA_ID ) || die( "Unable to find medium: " . WAPO_MEDIA_ID );

    my $feed_name = 'archive import';
    my $feed = $db->query( <<END, $medium->{ media_id }, $feed_name )->hash;
select f.*
    from feeds f
    where
        f.media_id = ? and
        f.name = ?
END

    return ( $medium, $feed ) if ( $feed );

    my $feed = {
        media_id    => $medium->{ media_id },
        name        => $feed_name,
        url         => 'http://articles.washingtonpost.com/01/Sep/2012',
        feed_status => 'inactive'
    };

    $feed = $db->create( 'feeds', $feed );

    return ( $medium, $feed );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my ( $medium, $feed ) = get_wapo_medium_and_feed( $db );

    for ( my $date = START_DATE ; $date lt END_DATE ; $date = MediaWords::Util::SQL::increment_day( $date ) )
    {
        print STDERR "date: $date\n";
        import_date( $db, $date, $medium, $feed );
    }
}

main();
