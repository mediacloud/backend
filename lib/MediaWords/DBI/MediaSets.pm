package MediaWords::DBI::MediaSets;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Encode;

use Data::Dumper;

# Creates a new media_set for the given media source
# also adds an entry to media_sets_media_map
sub create_for_medium
{
    my ( $db, $medium ) = @_;

    my $media_set = $db->create(
        'media_sets',
        {
            set_type => 'medium',
            name     => $medium->{ name },
            media_id => $medium->{ media_id }
        }
    );

    $db->create(
        'media_sets_media_map',
        {
            media_sets_id => $media_set->{ media_sets_id },
            media_id      => $medium->{ media_id }
        }
    );

    return $media_set;
}

1;
