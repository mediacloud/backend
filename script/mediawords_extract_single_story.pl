#!/usr/bin/env perl

# extract the text for the given story using the heuristic and crf extractors
use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::Util::HTML;
use MediaWords::StoryVectors;

sub get_extractor_results_for_story
{
    my ( $db, $story ) = @_;

    my $downloads =
      $db->query( "select * from downloads where stories_id = ? order by downloads_id", $story->{ stories_id } )->hashes;

    my $download_results = {};
    for my $download ( @{ $downloads } )
    {
        my $res = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download );
        $res->{ text } = join( "\n", map { $res->{ download_lines }->[ $_ ] } @{ $res->{ included_line_numbers } } );
        delete( $res->{ download_lines } );

        $download_results->{ $download->{ downloads_id } } = $res;
    }

    my $text = join( "\n****\n", map { html_strip( $_->{ text } ) } values( %{ $download_results } ) );

    return {
        text             => $text,
        download_results => $download_results,
        story            => $story
    };
}

sub main
{
    my ( $stories_id ) = @ARGV;

    die( "$0 < stories_id >" ) unless ( $stories_id );

    my $db = MediaWords::DB::connect_to_db;

    my $story = $db->find_by_id( 'stories', $stories_id );

    my $res = get_extractor_results_for_story( $db, $story );

    say STDERR $res->{ text };

    # print Dumper( $res );
}

main();
