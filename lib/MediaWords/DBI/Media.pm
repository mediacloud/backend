package MediaWords::DBI::Media;

#
# Various helper functions relating to media.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;
use XML::FeedPP;

# add a feed with the given url to the medium if the feed does not already exist and
# if the feed validates
sub add_feed_url_to_medium
{
    my ( $db, $medium, $feed_url ) = @_;

    my $feed_exists = $db->query( <<SQL, $medium->{ media_id }, $feed_url )->hash;
select * from feeds where media_id = ? and lower( url ) = lower( ? )
SQL

    return if $feed_exists;

    eval { XML::FeedPP->new( $feed_url ) };
    return if ( $@ );

    $db->create( 'feeds', { media_id => $medium->{ media_id }, name => 'csv imported feed', url => $feed_url } );
}

# Return true if the media sources has enough stories or is old enough that we
# are ready to analyze it for primary language, geo tagging, etc.
#
# Use the following rules to determine if the media source is ready:
#
# * return true if the medium has an active feed and more than 100 stories;
#
# * return false otherwise
sub medium_is_ready_for_analysis($$)
{
    my ( $db, $medium ) = @_;

    my $media_id = $medium->{ media_id };

    my $active_feed = $db->query( "select 1 from feeds where active = 't' and media_id = \$1", $media_id )->hash;

    return 0 unless ( $active_feed );

    my $first_story = $db->query( <<SQL, $media_id )->hash;
select * from stories where media_id = \$1 limit 1
SQL

    return 0 unless ( $first_story );

    my $story_101 = $db->query( <<SQL, $media_id )->hash;
    select * from stories where media_id = \$1 offset 101 limit 1
SQL

    return $story_101 ? 1 : 0;
}

1;
