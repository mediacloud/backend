#!/usr/bin/env perl

# set the pprimary language and subject country for media sources.  take care to run set both for a given
# media source at the same time so that we minimize solr reindexing.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::DBI::Media::PrimaryLanguage;
use MediaWords::DBI::Media::SubjectCountry;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $queue_functions = [
        \&MediaWords::DBI::Media::PrimaryLanguage::get_untagged_media_ids,
        \&MediaWords::DBI::Media::SubjectCountry::get_untagged_media_ids
    ];

    my $media_lookup = {};
    for my $f ( @{ $queue_functions } )
    {
        my $media_ids = $f->( $db );
        map { $media_lookup->{ $_ } = 1 } @{ $media_ids };
    }

    my $media_ids = [ sort { $a <=> $b } keys( %{ $media_lookup } ) ];

    my $media_ids_list = join( ',', @{ $media_ids } );

    my $active_media_ids = $db->query( <<SQL )->flat();
with active_media as (
    select distinct media_id from feeds where media_id in ( $media_ids_list ) and active = 't'
)

select media_id
    from media m
        join active_media am using ( media_id )
    where
        exists ( select 1 from stories s where s.media_id = m.media_id offset 101 limit 1 )
SQL

    my $num_active_media = scalar( @{ $active_media_ids } );

    DEBUG( "analyzing $num_active_media media ..." );

    my $i = 0;
    for my $media_id ( @{ $active_media_ids } )
    {
        my $medium = $db->require_by_id( 'media', $media_id );

        DEBUG( "medium $medium->{ name } $medium->{ media_id } [$i / $num_active_media]" );

        DEBUG( "analyzing language ..." );
        MediaWords::DBI::Media::PrimaryLanguage::set_primary_language( $db, $medium );

        DEBUG( "analyzing country ..." );
        MediaWords::DBI::Media::SubjectCountry::set_subject_country( $db, $medium );

        $i++;
    }

}

main();
