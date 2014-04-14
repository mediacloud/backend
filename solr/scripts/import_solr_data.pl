#!/usr/bin/env perl

# import a list of csvs into solr and write the dataimport.properties with the import date

use strict;

use File::Spec;

sub main
{
    my $files = [ @ARGV ];

    die( "usage: $0 <file 1> <file 2> ..." ) unless ( @{ $files } );

    my $pm = new Parallel::ForkManager( 4 );

    for my $file ( @{ $files } )
    {
        $pm->start and next;

        my $abs_file = File::Spec->rel2abs( $file );

        LWP::Simple::get(
"http://localhost:8983/solr/update/csv?stream.file=$abs_file&stream.contentType=text/plain;charset=utf-8&f.media_sets_id.split=true&f.media_sets_id.separator=;&f.tags_id_media.split=true&f.tags_id_media.separator=;&f.tags_id_stories.split=true&f.tags_id_stories.separator=;&f.tags_id_story_sentences.split=true&f.tags_id_story_sentences.separator=;&overwrite=false&skip=field_type,id,solr_import_date"
        );

        $pm->finish;
    }
}

main();
