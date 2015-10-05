package MediaWords::ImportStories::Feedly;

# import stories from a feedly feed
#
# in addition to ImportStories options, new accepts the following options:
#
# * feed_url - the url of a feed archived by feedly
#
# This module grabs historical stories from the feedly api

use strict;
use warnings;

use Moose;
with 'MediaWords::ImportStories';

use Data::Dumper;
use Encode;
use LWP::Simple;
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use URI::Escape;

use MediaWords::Util::JSON;
use MediaWords::Util::Web;

# number of stories to return in each feedly request
Readonly my $FEEDLY_COUNT => 10_000;

has 'feed_url' => ( is => 'rw', isa => 'Str', required => 1 );

has 'continuation_id' => ( is => 'rw', isa => 'Str',  required => 0 );
has 'end_of_feed'     => ( is => 'rw', isa => 'Bool', required => 0 );

# accept a hash generated from the feedly json response and return the list of story candidates.
# return only stories within the date range, and set end_of_feed if the latest story returned
# from feedly is older than start_date. stories are returned by feedly by latest collect_date,
# but fetching 1000 stories are a time should make it safe to compare the latest publish_date
# story to the $self->start_date
sub _get_stories_from_json_data
{
    my ( $self, $json_data ) = @_;

    my $latest_publish_date = 0;

    my $stories = [];
    for my $item ( @{ $json_data->{ items } } )
    {
        next unless ( $item->{ originId } );

        my $publish_date = MediaWords::Util::SQL::get_sql_date_from_epoch( $item->{ published } / 1000 );

        $latest_publish_date = $publish_date if ( $publish_date gt $latest_publish_date );

        next unless ( $self->story_is_in_date_range( $publish_date ) );

        my $guid = "feedly:$item->{ originId }";
        my $url =
          ( $item->{ alternate } && $item->{ alternate }->[ 0 ]->{ href } ) ? $item->{ alternate }->[ 0 ]->{ href } : $guid;

        my $story = {
            url          => $url,
            guid         => $guid,
            media_id     => $self->media_id,
            collect_date => MediaWords::Util::SQL::sql_now(),
            publish_date => $publish_date,
            title        => encode( 'utf8', $item->{ title } ),
            description  => encode( 'utf8', $item->{ summary }->{ content } )
        };

        push( @{ $stories }, $story );
    }

    say STDERR "latest_publish_date: $latest_publish_date";

    $self->end_of_feed( 1 ) if ( $latest_publish_date lt $self->start_date );

    return $stories;
}

# get one chunk of stories from the feedly api and save the continuation_id for the next call to the api.
# return undef if the end of the feed was reached in the previous call.  the end of feed is reached if either
# there are no more stories available from feedly in the previous call or if the oldest story returned in the previous
# call was older than $self->start_date.
sub _get_stories_from_feedly
{
    my ( $self ) = @_;

    say STDERR "get_stories_from_feedly " . ( $self->continuation_id || 'START' );

    return undef if ( $self->end_of_feed );

    my $ua = MediaWords::Util::Web::UserAgentDetermined;
    $ua->max_size( undef );
    $ua->timing( '1,15,60,300,300' );

    my $esc_feed_url = uri_escape( $self->feed_url );
    my $url          = "http://cloud.feedly.com/v3/streams/contents?streamId=feed/$esc_feed_url&count=$FEEDLY_COUNT";

    if ( $self->continuation_id )
    {
        my $esc_continuation_id = uri_escape( $self->continuation_id );
        $url = "$url&continuation=$esc_continuation_id";
    }

    my $res = $ua->get( $url );

    die( "error calling feedly api with url '$url': " . $res->as_string ) unless ( $res->is_success );

    my $json = $res->decoded_content;

    my $json_data = MediaWords::Util::JSON::decode_json( $json );

    die( "No feedly feed found for feed_url '" . $self->feed_url . "'" ) unless ( $json_data->{ title } );

    if ( my $continuation_id = $json_data->{ continuation } )
    {
        $self->continuation_id( $continuation_id );
    }
    else
    {
        $self->continuation_id( '' );
        $self->end_of_feed( 1 );
    }

    my $stories = $self->_get_stories_from_json_data( $json_data );

    return $stories;
}

sub get_new_stories
{
    my ( $self ) = @_;

    my $all_stories = [];
    while ( my $stories = $self->_get_stories_from_feedly )
    {
        say STDERR "get_new_stories: " . scalar( @{ $stories } ) . " stories found";
        push( @{ $all_stories }, @{ $stories } );
    }

    return $all_stories;
}

1;
