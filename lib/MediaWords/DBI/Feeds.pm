package MediaWords::DBI::Feeds;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

MediaWords::DBI::Feeds - various functions related to feeds

=cut

use strict;
use warnings;

=head1 FUNCTIONS

=head2 disable_feed( $db, $feeds_id )

(Temporarily) disable feed

=cut

sub disable_feed($$)
{
    my ( $db, $feeds_id ) = @_;

    $db->query(
        <<EOF,
        UPDATE feeds
        SET feed_status = 'inactive'
        WHERE feeds_id = ?
EOF
        $feeds_id
    );
}

1;
