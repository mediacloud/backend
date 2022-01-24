package MediaWords::DBI::Media::Lookup;

use Modern::Perl "2015";

use strict;
use warnings;

use MediaWords::CommonLibs;
use MediaWords::DBI::Media;
use MediaWords::Util::URL;

# get matching all media that match the normalized url of the given medium
sub _get_matching_media
{
    my ( $db, $url ) = @_;

    my $domain = MediaWords::Util::URL::get_url_distinctive_domain( $url );

    my $media = $db->query( <<SQL,
        SELECT
            m.*,
            mtm.tags_id AS spidered_tags_id
        FROM media AS m
            LEFT JOIN (
                media_tags_map AS mtm 
                    INNER JOIN tags AS t ON
                        mtm.tags_id = t.tags_id AND
                        t.tag = 'spidered'
                    INNER JOIN tag_sets AS ts ON
                        t.tag_sets_id = ts.tag_sets_id AND
                        ts.name = 'spidered'
            ) ON
                m.media_id = mtm.media_id
        WHERE m.url ILIKE ?
SQL
        '%' . $domain . '%'
    )->hashes;

    my $nu = MediaWords::Util::URL::normalize_url_lossy( $url );

    return [ grep { MediaWords::Util::URL::normalize_url_lossy( $_->{ url } ) eq $nu } @{ $media } ];
}

# sort sub to produce list of media sorted by spidered status, dup_media_id status, and the media_id
sub _compare_media_for_lookup_sort
{
    my ( $a, $b ) = @_;

    map { $_->{ _spider_sort } = $_->{ spidered_tags_id } ? 1 : 0; } ( $a, $b );
    map { $_->{ _dup_sort } = $_->{ dup_media_id } ? 1 : 0 } ( $a, $b );

    my $cmp =
         ( $a->{ _spider_sort } <=> $b->{ _spider_sort } )
      || ( $a->{ _dup_sort } <=> $b->{ _dup_sort } )
      || ( $a->{ media_id } <=> $b->{ media_id } );

    map { delete( $_->{ _spider_sort } ); delete( $_->{ _dup_sort } ) } ( $a, $b );

    return $cmp;
}

# find the medium by looking for an existing medium with the same normalized url.
# give prefernce first for non-spidered media and second for non-dup-media.
sub find_medium_by_url
{
    my ( $db, $url ) = @_;

    my $media = _get_matching_media( $db, $url );

    return undef unless ( @{ $media } );

    return $media->[ 0 ] if ( @{ $media } == 1 );

    $media = [ sort { _compare_media_for_lookup_sort( $a, $b ) } @{ $media } ];

    return $media->[ 0 ];
}

1;
