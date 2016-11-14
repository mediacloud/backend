package MediaWords::Crawler::Download::Feed::Syndicated;

#
# Handler for 'syndicated' feed downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::Download::DefaultFetcher', 'MediaWords::Crawler::Download::Feed::FeedHandler';

use MediaWords::Crawler::Engine;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

use Data::Dumper;
use Date::Parse;
use Encode;
use Feed::Scrape;
use Readonly;

# if $v is a scalar, return $v, else return undef.
# we need to do this to make sure we don't get a ref back from a feed object field
sub _no_ref
{
    my ( $v ) = @_;

    return ref( $v ) ? undef : $v;
}

# some guids are not in fact unique.  return the guid if it looks valid or undef if the guid looks like
# it is not unique
sub _sanitize_guid
{
    my ( $guid ) = @_;

    return undef unless ( defined( $guid ) );

    # ignore it if it is a url without a number or a path
    if ( MediaWords::Util::URL::is_http_url( $guid ) and $guid !~ /\d/ )
    {
        return undef;
    }

    return $guid;
}

# parse the feed.  return a (non-db-backed) story hash for each story found in the feed.
sub _get_stories_from_syndicated_feed($$$)
{
    my ( $decoded_content, $media_id, $download_time ) = @_;

    my $feed = Feed::Scrape->parse_feed( $decoded_content );

    die( "Unable to parse feed" ) unless $feed;

    my $items = [ $feed->get_item ];

    my $ret = [];

    for my $item ( @{ $items } )
    {
        my $guid = _sanitize_guid( _no_ref( $item->guid ) );

        my $url = _no_ref( $item->link() ) || _no_ref( $item->get( 'nnd:canonicalUrl' ) ) || $guid;
        $guid ||= $url;

        unless ( $url )
        {
            next;
        }

        $url  = substr( $url,  0, 1024 );
        $guid = substr( $guid, 0, 1024 );

        $url =~ s/[\n\r\s]//g;

        my $publish_date;

        if ( my $date_string = _no_ref( $item->pubDate() ) )
        {
            # Date::Parse is more robust at parsing date than postgres
            eval {
                $publish_date = MediaWords::Util::SQL::get_sql_date_from_epoch( Date::Parse::str2time( $date_string ) ); };
            if ( $@ )
            {
                $publish_date = $download_time;
                WARN "Error getting date from item pubDate ('" . $item->pubDate() . "') just using download time: $@";
            }
        }
        else
        {
            $publish_date = $download_time;
        }

        my $story = {
            url          => $url,
            guid         => $guid,
            media_id     => $media_id,
            publish_date => $publish_date,
            title        => _no_ref( $item->title ) || '(no title)',
            description  => _no_ref( $item->description ),
        };

        push @{ $ret }, $story;
    }

    return $ret;
}

# check whether the checksum of the concatenated urls of the stories in the feed matches the last such checksum for this
# feed.  If the checksums don't match, store the current checksum in the feed
sub _stories_checksum_matches_feed
{
    my ( $db, $feeds_id, $stories ) = @_;

    my $story_url_concat = join( '|', map { $_->{ url } } @{ $stories } );

    my $checksum = Digest::MD5::md5_hex( encode( 'utf8', $story_url_concat ) );

    my ( $matches ) = $db->query( <<END, $feeds_id, $checksum )->flat;
select 1 from feeds where feeds_id = ? and last_checksum = ?
END

    return 1 if ( $matches );

    $db->query( "update feeds set last_checksum = ? where feeds_id = ?", $checksum, $feeds_id );

    return 0;
}

# parse the feed content; create a story hash for each parsed story; check for a new url since the last
# feed download; if there is a new url, check whether each story is new, and if so add it to the database and
# ad a pending download for it.
# return new stories that were found in the feed.
sub add_stories_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $media_id = MediaWords::DBI::Downloads::get_media_id( $db, $download );
    my $download_time = $download->{ download_time };

    my $stories;
    eval { $stories = _get_stories_from_syndicated_feed( $decoded_content, $media_id, $download_time ); };
    if ( $@ )
    {
        die "Error processing feed for $download->{ url }: $@";
    }

    if ( _stories_checksum_matches_feed( $db, $download->{ feeds_id }, $stories ) )
    {
        return [];
    }

    my $new_stories = [ grep { MediaWords::DBI::Stories::is_new( $db, $_ ) } @{ $stories } ];

    my $story_ids = [];
    foreach my $story ( @{ $new_stories } )
    {
        MediaWords::DBI::Stories::add_story_and_content_download( $db, $story, $download );
        push( @{ $story_ids }, $story->{ stories_id } );
    }

    return $story_ids;
}

sub return_stories_to_be_extracted_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    # Syndicated feed itself is not a story of any sort, so nothing to extract
    # (stories from this feed will be extracted as 'content' downloads)
    return [];
}

1;
