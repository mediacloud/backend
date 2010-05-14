#!/usr/bin/perl -w

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use DBIx::Simple::MediaWords;

my $_stories_id_start       = 2900000;
my $_stories_id_window_size = 25000;
my $_stories_id_stop        = $_stories_id_start + $_stories_id_window_size;

sub get_stories_map_with_tags
{
    my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    print STDERR "grabing stories  -- " . localtime() . "\n";
    my $stories_rows = $dbh->query(
"select stories_id, media_id, publish_date from stories where stories_id >= ? and stories_id < ? and publish_date > (now() - interval '90 days')  order by stories_id",
        $_stories_id_start, $_stories_id_stop
    );

    print STDERR "creating stories hash map -- " . localtime() . "\n";

    my $stories_map = $stories_rows->map_hashes( 'stories_id' );

    {
        print STDERR "grabbing from  stories_tags_map  -- " . localtime() . "\n";

        my $stories_tags_map_rows =
          $dbh->query( "select * from stories_tags_map where  stories_id >= ? and stories_id < ? order by stories_id ",
            $_stories_id_start, $_stories_id_stop );

        print STDERR "filling in tag_info in stories_map -- " . localtime() . "\n";

        $stories_tags_map_rows->bind( my ( $stories_tag_map_id, $stories_id, $tags_id ) );

        while ( $stories_tags_map_rows->fetch )
        {
            if ( $stories_map->{ $stories_id } )
            {
                $stories_map->{ $stories_id }->{ tag_list_hash }->{ int( $tags_id ) } = 1;

                #            print STDERR "($stories_tag_map_id, $stories_id, $tags_id) \n";
            }
        }
    }

    return $stories_map;

}

sub get_tag_set
{
    ( my $tags_id ) = @_;

    return get_tags_map()->{ $tags_id }->{ tag_sets_id };
}

my $_tags_map;

sub get_tags_map
{

    if ( !defined( $_tags_map ) )
    {
        my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
          || die DBIx::Simple::MediaWords->error;

        print STDERR "grabbing from tags  -- " . localtime() . "\n";

        my $tags_rows = $dbh->query( "select tags_id, tag_sets_id from tags " );

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

        #        if ($stories_map->{$story_id}->{tag_list_hash})
        {
            my @tag_list = keys %{ $stories_map->{ $story_id }->{ tag_list_hash } };

            my $media_id;
            $media_id = int( $stories_map->{ $story_id }->{ media_id } );

            foreach my $tag ( @tag_list )
            {

                $media_tag_hash_count->{ $media_id }->{ int( $tag ) } ||= {};

                foreach my $tag_tag ( @tag_list )
                {
                    if (   ( $tag != $tag_tag )
                        && ( get_tag_set( $tag ) == get_tag_set( $tag_tag ) ) )
                    {
                        $media_tag_hash_count->{ $media_id }->{ int( $tag ) }->{ int( $tag_tag ) }++;
                    }
                }
            }
        }

        #TODO IS THIS SAFE?
        delete( $stories_map->{ $story_id } );
        $completed_stories++;
    }

    return $media_tag_hash_count;
}

sub get_max_stories_id
{
    my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    my $max_stories_id_row = $dbh->query( "select max(stories_id) as max_id from stories" ) || die $dbh->error;

    my $max_stories_id = $max_stories_id_row->hash()->{ max_id };

    return $max_stories_id;
}

sub scroll_stories_id_window
{
    $_stories_id_start = $_stories_id_stop;
    $_stories_id_stop  = $_stories_id_start + $_stories_id_window_size;

    print STDERR "story_id windows: $_stories_id_start -- $_stories_id_stop   (max_stories_id: " . get_max_stories_id() .
      ")  -- " .
      localtime() . "\n";
}

sub get_media_tag_hash_count
{

    my $media_tag_hash_count = {};

    my $stories_map = get_stories_map_with_tags();

    $media_tag_hash_count = get_media_tag_hash_count_from_stories_map( $media_tag_hash_count, $stories_map );

    return $media_tag_hash_count;
}

sub insert_rows_for_media_id
{
    my ( $current_media_tag_hash_count, $media_id ) = @_;

    my $rows_for_media_id = 0;

    my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    #$dbh->dbh->{AutoCommit} = 0;

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

            if ( !@top_ten_tag_tags )
            {
                next;
            }

      #                 print STDERR 'unshortened:' . ( join " ,", @top_ten_tag_tags ) . "\n";
      #                 print STDERR "\t" . join " ,", map { $current_media_tag_hash_count->{$tag}->{$_} } @top_ten_tag_tags;
      #                 print STDERR "\n";

            if ( @top_ten_tag_tags > 10 )
            {
                splice @top_ten_tag_tags, 10;
            }

      #                 print STDERR "shortened:  " . ( join " ,", @top_ten_tag_tags ) . "\n";
      #                 print STDERR "\t" . join " ,", map { $current_media_tag_hash_count->{$tag}->{$_} } @top_ten_tag_tags;
      #                 print STDERR "\n";

            foreach my $tag_tag ( @top_ten_tag_tags )
            {
                my $tag_count = $current_media_tag_hash_count->{ $tag }->{ $tag_tag };

                my $row_to_insert = {
                    tags_id     => int( $tag ),
                    tag_tags_id => int( $tag_tag ),
                    tag_sets_id => int( $tag_sets_id ),
                    media_id    => int( $media_id ),
                    tag_count   => int( $tag_count )
                };

                #                     print "Row to insert ";

                #                     my @temp_str = %{$row_to_insert};
                #                     print join " ," , @temp_str;
                #                     print STDERR "\n";

                $dbh->query(
"INSERT INTO media_tag_tag_counts_new (media_id, tags_id, tag_tags_id, tag_sets_id, tag_count) values (?,?,?,?,?)",
                    $media_id, $tag, $tag_tag, $tag_sets_id, $tag_count )
                  || warn $dbh->error;
                $rows_for_media_id++;

                #push @{$rows_to_insert}, $row_to_insert;
            }
        }

        #            print STDERR "\n";
    }
    print STDERR "\t committing  -- " . localtime() . "\n";
    $dbh->commit;
    print STDERR "\t $rows_for_media_id rows inserted  -- " . localtime() . "\n";
}

sub get_rows_to_insert
{

    # my $tags_map;
    my $media_tag_hash_count = get_media_tag_hash_count();

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

sub create_media_tag_tag_counts_temp_table
{
    my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    print STDERR "creating media_tag_tag_counts_new table \n";

    eval { $dbh->query( "DROP TABLE if exists media_tag_tag_counts_new" ); };

    $dbh->query(
"create table media_tag_tag_counts_new  (media_id integer NOT NULL, tag_sets_id integer NOT NULL, tags_id integer NOT NULL, tag_tags_id integer NOT NULL, tag_count integer NOT NULL) "
    ) || die $dbh->error;

    my $now = time();

    $dbh->query(
"create unique index media_tag_tag_counts_media_and_tag_and_tag_tag_$now on media_tag_tag_counts_new(media_id, tags_id, tag_tags_id)"
    );
}

sub main

{
    print STDERR "creating media tag tag counts table\n";

    #the extractor adds new tags but we cache the tags table
    print STDERR "WARNING MAKE SURE THE EXTRACTOR IS NOT RUNNING\n";

    create_media_tag_tag_counts_temp_table();

    my $max_stories_id = get_max_stories_id();

    while ( $_stories_id_start <= $max_stories_id )
    {
        my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
          || die DBIx::Simple::MediaWords->error;

        my $rows_to_insert = get_rows_to_insert();

        scroll_stories_id_window();
    }

    my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    print STDERR "creating indices ... -- " . localtime() . "\n";
    my $now = time();
    $dbh->query( "create index media_tag_tag_counts_count_$now on media_tag_tag_counts_new(tag_count)" );
    $dbh->query( "create index media_tag_tag_counts_tag_$now on media_tag_tag_counts_new(tags_id)" );
    $dbh->query( "create index media_tag_tag_counts_tag_tag_$now on media_tag_tag_counts_new(tag_tags_id)" );
    $dbh->query( "create index media_tag_tag_counts_media_$now on media_tag_tag_counts_new(media_id)" );
    $dbh->query(
"create index media_tag_tag_counts_media_and_tag_and_tag_tag_$now on media_tag_tag_counts_new(media_id, tags_id, tag_tags_id)"
    );
    $dbh->query( "create index media_tag_tag_counts_media_and_tag_$now on media_tag_tag_counts_new(media_id, tags_id)" );
    print STDERR "replacing table ... -- " . localtime() . "\n";
    eval { $dbh->query( "drop table media_tag_tag_counts" ) };
    $dbh->query( "alter table media_tag_tag_counts_new rename to media_tag_tag_counts" );

    print STDERR "analyzing table ... -- " . localtime() . "\n";
    $dbh->query( "analyze media_tag_tag_counts" );
}

main();
