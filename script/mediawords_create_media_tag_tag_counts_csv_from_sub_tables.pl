#!/usr/bin/env perl

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use List::MoreUtils qw(uniq any);

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../script";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use Getopt::Long;
use TableCreationUtils;
use Readonly;
use MediaWords::DBI::StoriesTagsMapMediaSubtables;

sub get_stories_map_with_tags
{
    my ( $sub_table_media_id ) = @_;

    purge_tag_tag_set_map();

    my $dbh = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    print STDERR "grabing stories  -- " . localtime() . "\n";

    my $stories_tags_map_sub_table_name =
      MediaWords::DBI::StoriesTagsMapMediaSubtables::_get_sub_table_full_name_for_media_id( $sub_table_media_id );
    my $stories_tags_map_rows = $dbh->query_only_warn_on_error(
        "select media_id, stories_id, tags_id, tag_sets_id  from " . $stories_tags_map_sub_table_name .
          " where publish_date > (now() - interval '90 days') order by stories_id" );

    $stories_tags_map_rows->bind( my ( $media_id, $stories_id, $tags_id, $tag_sets_id ) );
    print STDERR "creating stories hash map -- " . localtime() . "\n";

    my $stories_map = {};

    while ( $stories_tags_map_rows->fetch )
    {
        if ( !defined( $stories_map->{ $stories_id } ) )
        {
            $stories_map->{ $stories_id }->{ media_id } = $media_id;
        }

        add_tag_tag_set_mapping( $tags_id, $tag_sets_id );
        $stories_map->{ $stories_id }->{ tag_list_hash }->{ int( $tags_id ) } = 1;
    }

    return $stories_map;
}

my $_tag_sets_id_for_tags_id = {};

sub purge_tag_tag_set_map
{
    $_tag_sets_id_for_tags_id = {};
}

sub add_tag_tag_set_mapping
{
    ( my $tags_id, my $tag_sets_id ) = @_;

    $_tag_sets_id_for_tags_id->{ $tags_id } = $tag_sets_id;
}

sub get_tag_string
{
    ( my $tags_id, my $dbh ) = @_;

    my $tag_string;

    #return "Foo_barXXXX";
    #    $tag_string = $dbh->find_by_id('tags', $tags_id)->{tag};

    $tag_string = get_tags_map()->{ $tags_id }->{ tag };
    die "mssing tag_string for $tags_id " unless ( $tag_string );

    return $tag_string;
}

sub get_tag_set
{
    ( my $tags_id ) = @_;

    #return 13;
    return $_tag_sets_id_for_tags_id->{ $tags_id };
}

my $_tags_map;

sub get_tags_map
{

    if ( !defined( $_tags_map ) )
    {
        my $dbh = MediaWords::DB::connect_to_db()
          || die DBIx::Simple::MediaWords->error;

        print STDERR "grabbing from tags  -- " . localtime() . "\n";

        my $tags_rows = $dbh->query( "select tags_id, tag_sets_id, tag from tags " );

        print STDERR "creating tags hash map -- " . localtime() . "\n";

        my $tags_map = $tags_rows->map_hashes( 'tags_id' );

        $_tags_map = $tags_map;
    }

    return $_tags_map;
}

sub get_media_tag_hash_count_from_stories_map
{
    my ( $media_tag_hash_count, $stories_map ) = @_;

    print STDERR "filling in tag_info in media_tag_hash_count map -- " . localtime() . "\n";

    my $number_of_stories = scalar( keys %{ $stories_map } );

    my $completed_stories = 0;

    my @story_ids = keys %{ $stories_map };

    foreach my $story_id ( @story_ids )
    {

        if ( ( $completed_stories % 1000 ) == 0 )
        {
            print STDERR "Processed $completed_stories stories out of $number_of_stories -- " . localtime() . "\n";
        }

        my @tag_list = keys %{ $stories_map->{ $story_id }->{ tag_list_hash } };

        my $media_id;
        $media_id = int( $stories_map->{ $story_id }->{ media_id } );

        for ( my $i = 0 ; $i < scalar( @tag_list ) ; $i++ )
        {
            my $tag = $tag_list[ $i ];

            $media_tag_hash_count->{ $media_id }->{ int( $tag ) } ||= {};
            for ( my $j = ( $i + 1 ) ; $j < scalar( @tag_list ) ; $j++ )
            {
                my $tag_tag = $tag_list[ $j ];
                if (   ( $tag != $tag_tag )
                    && ( get_tag_set( $tag ) == get_tag_set( $tag_tag ) ) )
                {
                    $media_tag_hash_count->{ $media_id }->{ int( $tag ) }->{ int( $tag_tag ) }++;
                    $media_tag_hash_count->{ $media_id }->{ int( $tag_tag ) }->{ int( $tag ) }++;
                }
            }
        }

        #TODO IS THIS SAFE?
        delete( $stories_map->{ $story_id } );
        $completed_stories++;
    }

    return $media_tag_hash_count;
}

sub get_media_tag_hash_count
{

    my ( $media_id ) = @_;

    my $media_tag_hash_count = {};

    my $stories_map = get_stories_map_with_tags( $media_id );

    $media_tag_hash_count = get_media_tag_hash_count_from_stories_map( $media_tag_hash_count, $stories_map );

    return $media_tag_hash_count;
}

sub get_media_id_specific_black_listed_tags
{
    my ( $dbh, $media_id ) = @_;

    return $dbh->query( "SELECT tags_id from media_black_listed_tags where media_id = ? ", $media_id )->flat;
}

sub insert_rows_for_media_id
{
    my ( $current_media_tag_hash_count, $media_id ) = @_;

    my $rows_for_media_id = 0;

    my $dbh = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    my $media_name = $dbh->find_by_id( 'media', $media_id )->{ name };
    $media_name = lc( $media_name );
    print STDERR "\t Media Name: $media_name\n";

    my $total_pivot_tags_for_source = scalar( keys %{ $current_media_tag_hash_count } );

    my $pivot_tags_processed = 0;

    print STDERR "start grabbing black listed tags_ids " . localtime() . "\n";
    my @media_black_listed_tags = get_media_id_specific_black_listed_tags( $dbh, $media_id );
    print STDERR "finished grabbing black listed tags_ids " . localtime() . "\n";

    my $tag_matches_source_name = { map { $_, 1 } @media_black_listed_tags };

    foreach my $tag ( sort { $a <=> $b } keys %{ $current_media_tag_hash_count } )
    {

        #            print "\tTAG '$tag': ";
        if ( $current_media_tag_hash_count->{ $tag } )
        {
            my $tag_sets_id = get_tag_set( $tag );

            my @top_ten_tag_tags = (
                sort { $current_media_tag_hash_count->{ $tag }->{ $b } <=> $current_media_tag_hash_count->{ $tag }->{ $a } }
                  keys %{ $current_media_tag_hash_count->{ $tag } }
            );

            @top_ten_tag_tags = grep { ( !TableCreationUtils::is_black_listed_tag( $_ ) ) } @top_ten_tag_tags;

            if ( !@top_ten_tag_tags )
            {
                next;
            }

            my $tag_tag_rows_inserted = 0;

            foreach my $tag_tag ( @top_ten_tag_tags )
            {
                if ( defined( $tag_matches_source_name->{ $tag_tag } ) )
                {

                    #print STDERR "Found $tag_tag id in hash\n";
                    if ( $tag_matches_source_name->{ $tag_tag } )
                    {
                        next;
                    }
                }

                my $tag_count = $current_media_tag_hash_count->{ $tag }->{ $tag_tag };

                print OUTPUT_FILE "$media_id, $tag, $tag_tag, $tag_sets_id, $tag_count\n";

                #map { die unless $_ eq int($_) } ($media_id, $tag, $tag_tag, $tag_sets_id, $tag_count);

                $rows_for_media_id++;
                $tag_tag_rows_inserted++;

                if ( $tag_tag_rows_inserted >= 10 )
                {
                    last;
                }
            }
        }

        $pivot_tags_processed++;

        if ( ( $pivot_tags_processed % 1000 ) == 0 )
        {
            print STDERR "\t $pivot_tags_processed out of $total_pivot_tags_for_source -- " . localtime() . "\n";
            print STDERR "\t ($rows_for_media_id rows inserted  for media_id) -- " . localtime() . "\n";

        }

        #            print STDERR "\n";
    }

    print STDERR "\t $rows_for_media_id rows inserted  -- " . localtime() . "\n";
}

sub get_rows_to_insert
{

    my ( $media_id ) = @_;

    # my $tags_map;
    my $media_tag_hash_count = get_media_tag_hash_count( $media_id );

    my $rows_to_insert = [];

    print STDERR "start creating rows to insert -- " . localtime() . "\n";

    my @media_id_list = sort { $a <=> $b } keys %{ $media_tag_hash_count };

    foreach my $media_id ( @media_id_list )
    {
        print STDERR "Media_id: $media_id  -- " . localtime() . "\n";

        my $current_media_tag_hash_count = $media_tag_hash_count->{ $media_id };

        insert_rows_for_media_id( $current_media_tag_hash_count, $media_id );

        #TODO FREE MEMORY -- IS THIS SAFE?
        delete( $media_tag_hash_count->{ $media_id } );
    }

    return $rows_to_insert;
}

sub main

{
    my $csv_file = '';

    GetOptions( 'csv_file=s' => \$csv_file )
      or die "USAGE: ./mediawords_create_media_tag_tag_counts_from_sub_tables --csv_file=FILE_NAME\n";

    die "USAGE: ./mediawords_create_media_tag_tag_counts_csv_from_sub_tables --csv_file=FILE_NAME \n" unless $csv_file;

    open( OUTPUT_FILE, "> $csv_file" ) or die "can't open file: $!\n";

    print STDERR "starting --  " . localtime() . "\n";

    my @media_ids =
      MediaWords::DBI::StoriesTagsMapMediaSubtables::get_media_ids_with_subtables(
        TableCreationUtils::get_database_handle() );

    #@media_ids = qw (1);

    #print "Media_ids:\n";
    #print join ",\n", map { "'$_'" } @media_ids;
    foreach my $media_id ( @media_ids )
    {
        print STDERR "processing media_id $media_id  -- " . localtime() . "\n";
        my $rows_to_insert = get_rows_to_insert( $media_id );
    }

    print STDERR "finished -- " . localtime() . "\n";
}

main();
