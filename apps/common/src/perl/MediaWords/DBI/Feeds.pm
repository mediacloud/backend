package MediaWords::DBI::Feeds;

#
# Various functions related to feeds
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Digest::MD5 qw/md5_hex/;
use Encode;

# check whether the checksum of the concatenated urls of the stories in the feed matches the last such checksum for this
# feed.  If the checksums don't match, store the current checksum in the feed
sub stories_checksum_matches_feed
{
    my ( $db, $feeds_id, $stories ) = @_;

    my $story_url_concat = join( '|', map { $_->{ url } } @{ $stories } );

    my $checksum = md5_hex( encode( 'utf8', $story_url_concat ) );

    my ( $matches ) = $db->query(
        <<SQL,
        SELECT 1
        FROM feeds
        WHERE feeds_id = ?
          AND last_checksum = ?
SQL
        $feeds_id, $checksum
    )->flat;

    return 1 if ( $matches );

    $db->query( 'UPDATE feeds SET last_checksum = ? WHERE feeds_id = ?', $checksum, $feeds_id );

    return 0;
}

# (Temporarily) disable feed
sub disable_feed($$)
{
    my ( $db, $feeds_id ) = @_;

    $db->query(
        <<EOF,
        UPDATE feeds
        SET active = 'f'
        WHERE feeds_id = ?
EOF
        $feeds_id
    );
}

1;
