#!/usr/bin/env perl

# parse bitly_fetch_story_stats log for errors and generate an error report.  if an error type is specified
# on the command line, resubmit stories generating those errors for reprocessing

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::Bitly::FetchStoryStats;

sub main
{
    my ( $resubmit_error_type ) = @ARGV;

    my $error_types = {};

    while ( my $line = <STDIN> )
    {
        next unless ( $line =~ /error while/i );
        chomp( $line );

        my $error_type_rules = [
            [ qr/for story (\d+).*created_by/i,           'created_by' ],
            [ qr/for story (\d+).*unable to lookup url/i, 'lookup' ],
            [ qr/for story (\d+).*non-200 HTTP status/i,  'non_200_http' ],
            [ qr/for story (\d+).*is not a HTTP.*URL/i,   'not_url' ],
            [ qr/for story (\d+)/i,                       'unknown_story' ],
            [ qr/.*/,                                     'unknown' ]
        ];

        for my $rule ( @{ $error_type_rules } )
        {
            if ( $line =~ $rule->[ 0 ] )
            {
                push( @{ $error_types->{ $rule->[ 1 ] } }, $1 );

                TRACE( "UNKNOWN: $line" ) if ( $rule->[ 1 ] =~ /unknown/ );
                last;
            }
        }
    }

    for my $error_type ( keys( %{ $error_types } ) )
    {
        say( "$error_type: " . scalar( @{ $error_types->{ $error_type } } ) );
    }

    if ( $resubmit_error_type )
    {
        die( "No errors of type '$resubmit_error_type'" ) unless ( $error_types->{ $resubmit_error_type } );

        for my $stories_id ( @{ $error_types->{ $resubmit_error_type } } )
        {
            DEBUG( "add story to queue: $stories_id" );
            MediaWords::Job::Bitly::FetchStoryStats->add_to_queue( { stories_id => $stories_id }, 'low' );
        }
    }
}

main();
