#!/usr/bin/env perl

#
# test accuracy of ap syndication detection by comparing results to manually
# coded stories in scratch.ap_stories_coded
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::Controller::Api::V2::StoriesBase;

sub get_story_content
{
    my ( $db, $story ) = @_;

    return '' unless ( $story && $story->{ download } && ( $story->{ download }->{ state } = 'success' ) );

    my $content_ref;

    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $story->{ download } ) };
    if ( $@ || !$content_ref )
    {
        warn( "error fetching content: $@" );
        return 0;
    }

    return $$content_ref;
}

# run ap detection on get hash of story ids, for which each story id key associated
# with a true value indicates that the detection algorithm thinks that story id
# is an ap syndicated story
sub get_detected_ap_stories_lookup
{
    my ( $db, $stories ) = @_;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );
    my $detected_ap_stories_ids = MediaWords::Controller::Api::V2::StoriesBase::_get_ap_stories_ids( $db, $ids_table );

    my $detected_ap_lookup = {};
    map { $detected_ap_lookup->{ $_->{ stories_id } } = $_->{ ap_stories_id } } @{ $detected_ap_stories_ids };

    return $detected_ap_lookup;
}

sub get_ap_detection_dup_sentences
{
    my ( $db, $story ) = @_;

    my $detected_ap_lookup = get_detected_ap_stories_lookup( $db, [ $story ] );
    my $ap_detection = $detected_ap_lookup->{ $story->{ stories_id } } ? 1 : 0;

    return $ap_detection;
}

sub get_ap_detection_cached_method
{
    my ( $db, $story, $method ) = @_;

    my $ap_story = $db->query( <<SQL, $story->{ stories_id }, $method )->hash;
select * from scratch.ap_stories_detected
    where stories_id = ? and
        syndicated = ?
SQL

    return ( $ap_story && ( $ap_story->{ syndicated } ) );
}

sub get_ap_detection_pattern
{
    my ( $db, $story ) = @_;

    my $content = get_story_content( $db, $story );

    return ( $content =~ /["'].{0,8}associated press.{0,8}["']/i ) ? 1 : 0;
}

sub get_ap_detection_text_ap
{
    my ( $db, $story ) = @_;

    my $text = MediaWords::DBI::Stories::get_text( $db, $story );

    return ( $text =~ /\(ap\)/i ) ? 1 : 0;
}

# do the most aggressive version of looking for 'associated press' or '(ap)' in the whole html of the story.
sub get_ap_detection_max_ap_text
{
    my ( $db, $story ) = @_;

    my $content = get_story_content( $db, $story );

    return ( $content =~ /associated press|\(ap\)/i ) ? 1 : 0;
}

sub get_ap_detection_pattern_20160203
{
    my ( $db, $story ) = @_;

    my $content = get_story_content( $db, $story );

    return ( $content =~ /["'\|].{0,8}associated press.{0,8}["'\|]|ap_online/i ) ? 1 : 0;

    #return ( $content =~ /["'\|].{0,8}associated press.{0,8}["'\|]/i ) ? 1 : 0;
    #return ( $content =~ /["'].{0,8}associated press.{0,8}["']/i ) ? 1 : 0;
}

# does the detection algorithm think this is an ap syndicated story
sub get_ap_detection
{
    my ( $db, $story, $method ) = @_;

    #my $ap_detection = get_ap_detection_dup_sentences( $db, $story ) || get_ap_detection_pattern( $db, $story );
    my $ap_detection = get_ap_detection_pattern_20160203( $db, $story );

    return $ap_detection;
}

sub get_skip_stories_lookup
{
    my ( $db, $stories, $method ) = @_;

    my $stories_id_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $skip_stories = $db->query( <<SQL, $method )->hashes;
select *
    from scratch.ap_stories_detected
    where stories_id in ( $stories_id_list ) and
        method = ?
SQL

    my $skip_stories_lookup = {};
    map { $skip_stories_lookup->{ $_->{ stories_id } } = 1; } @{ $skip_stories };

    return $skip_stories_lookup;
}

sub insert_detected_stories
{
    my ( $db, $stories, $method ) = @_;

    return if ( !@{ $stories } );

    my $q_method = $db->dbh->quote( $method );

    my $values = [];
    for my $s ( @{ $stories } )
    {
        my $b_ap = $s->{ ap_detection } ? 'true' : 'false';

        push( @{ $values }, "($s->{ stories_id },$q_method,$b_ap)" );
    }

    my $values_list = join( ',', @{ $values } );

    $db->query( <<SQL );
insert into scratch.ap_stories_detected ( stories_id, method, syndicated )
values $values_list
SQL

}

sub attach_downloads_to_stories
{
    my ( $db, $stories ) = @_;

    my $stories_id_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $downloads = $db->query( <<SQL )->hashes;
select * from downloads
    where stories_id in ( $stories_id_list )
    order by downloads_id;
SQL

    my $downloads_lookup = {};
    for my $download ( @{ $downloads } )
    {
        next if ( $downloads_lookup->{ $download->{ stories_id } } );

        $downloads_lookup->{ $download->{ stories_id } } = $download;
    }

    map { $_->{ download } = $downloads_lookup->{ $_->{ stories_id } } } @{ $stories };
}

sub main
{
    my ( $method ) = @ARGV;

    die( "usage: $0 < method >" ) unless ( $method );

    my $db = MediaWords::DB::connect_to_db;

    my $stories = $db->query( <<SQL )->hashes;
select
        s.*, ap.syndication, ap.url_status
from
    stories s
    join scratch.ap_stories_coded ap on ( s.stories_id = ap.stories_id )
SQL

    attach_downloads_to_stories( $db, $stories );

    #my $detected_ap_lookup = get_detected_ap_stories_lookup( $db, $stories );

    my $skip_stories_lookup = get_skip_stories_lookup( $db, $stories, $method );

    my $i            = 0;
    my $insert_queue = [];
    for my $story ( @{ $stories } )
    {
        next if ( $skip_stories_lookup->{ $story->{ stories_id } } );
        next if ( $story->{ syndication } eq 'unknown' );

        $story->{ ap_detection } = get_ap_detection( $db, $story, $method );

        push( @{ $insert_queue }, $story );

        $i++;
        if ( !( $i % 100 ) )
        {
            print STDERR "[$i] ...\n";
            insert_detected_stories( $db, $insert_queue, $method );
            $insert_queue = [];
        }
    }

    insert_detected_stories( $db, $insert_queue, $method );
}

main();
