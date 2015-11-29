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
use MediaWords::DBI::Stories;
use MediaWords::Controller::Api::V2::StoriesBase;

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

sub get_ap_detection_pattern
{
    my ( $db, $story ) = @_;

    my $content_ref;

    eval { $content_ref = MediaWords::DBI::Stories::get_content_for_first_download( $db, $story ) };
    if ( $@ || !$content_ref )
    {
        warn( "error fetching content: $@" );
        return 0;
    }

    my $search_text = substr( $$content_ref, 0, int( length( $$content_ref ) / 3 ) );

    return ( $search_text =~ /["'].{0,8}associated press.{0,8}["']/i ) ? 1 : 0;
}

sub get_ap_detection_text_ap
{
    my ( $db, $story ) = @_;

    my $text = MediaWords::DBI::Stories::get_text( $db, $story );

    return ( $text =~ /\(ap\)/i ) ? 1 : 0;
}

# does the detection algorithm think this is an ap syndicated story
sub get_ap_detection
{
    my ( $db, $story, $method ) = @_;

    my $ap_story_detected = $db->query( <<SQL, $story->{ stories_id }, $method )->hash;
select * from scratch.ap_stories_detected where stories_id = ? and method = ?
SQL

    return $ap_story_detected->{ syndicated } if ( $ap_story_detected );

    print STDERR "DETECT ...\n";

    #my $ap_detection = get_ap_detection_dup_sentences( $db, $story ) || get_ap_detection_pattern( $db, $story );
    my $ap_detection =
         get_ap_detection_text_ap( $db, $story )
      || get_ap_detection_pattern( $db, $story )
      || get_ap_detection_dup_sentences( $db, $story );

    $db->query( <<SQL, $story->{ stories_id }, $method, $ap_detection );
insert into scratch.ap_stories_detected ( stories_id, method, syndicated )
    values( ?, ?, ? )
SQL

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

    #my $detected_ap_lookup = get_detected_ap_stories_lookup( $db, $stories );

    my ( $num_correct, $num_false_positive, $num_false_negative, $num_unknown ) = ( 0, 0, 0, 0 );
    my $i = 0;
    for my $story ( @{ $stories } )
    {
        print STDERR "$story->{ stories_id } [" . $i++ . "] ...\n";
        if ( $story->{ syndication } eq 'unknown' )
        {
            $num_unknown++;
            next;
        }

        my $ap_coded = ( $story->{ syndication } eq 'ap' );
        my $ap_detection = get_ap_detection( $db, $story, $method );

        if ( ( $ap_detection && $ap_coded ) || ( !$ap_detection && !$ap_coded ) )
        {
            $num_correct++;
        }
        elsif ( $ap_coded )
        {
            $num_false_negative++;
        }
        elsif ( $ap_detection )
        {
            $num_false_positive++;
        }
        else
        {
            die( "impossible validation result" );
        }
    }

    my $num_total = scalar( @{ $stories } );

    print <<END;
total:      $num_total
correct:    $num_correct
false pos:  $num_false_positive
false neg:  $num_false_negative
END
}

main();
