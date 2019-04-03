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
    my $db = MediaWords::DB::connect_to_db;

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

    for my $media_id ( @{ $media_ids } )
    {
        my $medium = $db->require_by_id( 'media', $media_id );

        if ( !MediaWords::DBI::Media::medium_is_ready_for_analysis( $db, $medium ) )
        {
            TRACE( "medium $medium->{ name } [ $medium->{ media_id } ]: NOT READY" );
            next;
        }

        DEBUG( "medium $medium->{ name } [ $medium->{ media_id } ]" );

        DEBUG( "analyzing language ..." );
        MediaWords::DBI::Media::PrimaryLanguage::set_primary_language( $db, $medium );
    }

}

main();
