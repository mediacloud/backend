#!/usr/bin/env perl
#
# set the primary language for media sources.  take care to run set both for a given
# media source at the same time so that we minimize solr reindexing.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::DBI::Media::PrimaryLanguage;

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $queue_functions = [
        \&MediaWords::DBI::Media::PrimaryLanguage::get_untagged_media_ids,
    ];

    my $media_lookup = {};
    for my $f ( @{ $queue_functions } )
    {
        my $media_ids = $f->( $db );
        map { $media_lookup->{ $_ } = 1 } @{ $media_ids };
    }

    my $media_ids = [ sort { $a <=> $b } keys( %{ $media_lookup } ) ];

    my $media_ids_list = join( ',', @{ $media_ids } );

    my $active_media_ids = $db->query( <<SQL
        WITH active_media AS (
            SELECT DISTINCT media_id
            FROM feeds
            WHERE
                media_id IN ($media_ids_list) AND
                active = 't'
        )

        SELECT media_id
        FROM media AS m
            INNER JOIN active_media AS am USING (media_id)
        WHERE
            EXISTS (
                SELECT 1
                FROM stories AS s
                WHERE s.media_id = m.media_id
                OFFSET 101
                LIMIT 1
            )
SQL
    )->flat();

    my $num_active_media = scalar( @{ $active_media_ids } );

    DEBUG( "analyzing $num_active_media media ..." );

    my $i = 0;
    for my $media_id ( @{ $active_media_ids } )
    {
        my $medium = $db->require_by_id( 'media', $media_id );

        DEBUG( "medium $medium->{ name } $medium->{ media_id } [$i / $num_active_media]" );

        DEBUG( "analyzing language ..." );
        MediaWords::DBI::Media::PrimaryLanguage::set_primary_language( $db, $medium );

        $i++;
    }

}

main();
