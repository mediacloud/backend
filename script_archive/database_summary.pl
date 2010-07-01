#!/usr/bin/perl -w

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use DBI;
use DBIx::Simple;
use DBIx::Simple::MediaWords;
use Locale::Country;
use URI::Escape;
use List::Uniq ':all';
use List::Util qw (max min reduce sum);
use List::Pairwise qw(mapp grepp map_pairwise);
use URI;
use URI::Split;
use Data::Dumper;
use Array::Compare;
use Hash::Merge;
use Carp;
use Readonly;
use XML::LibXML;
use XML::LibXML::XPathContext;
use Text::Table;
use Math::Round;

sub node_list_to_hash
{
    my ( $node_list ) = @_;

    #filter out nonelement nodes
    return { map { $_->localname => $_->textContent } grep { $_->nodeType == 1 } ( @{ $node_list } ) };
}

Readonly my $_debug_mode => 0;

sub generate_results_delta
{
    my ( $new_results, $old_results ) = @_;

    my $ret = {};

    #print STDERR "Old results:\n" . (%$old_results)[1]->toString . "\n";

    my $new_time = ( %$new_results )[ 0 ];
    my $old_time = ( %$old_results )[ 0 ];

    my $new_xml_results = ( %$new_results )[ 1 ];
    my $old_xml_results = ( %$old_results )[ 1 ];

    my $time_delta = $new_time - $old_time;
    my $hours_delta = sprintf( "%.2f", $time_delta / ( 60 * 60 ) );

    if ( $hours_delta > 4 )
    {
        $hours_delta = round( $hours_delta );
    }
    $ret->{ _hours } = $hours_delta;

    my $old_results_hash = node_list_to_hash( [ $old_xml_results->childNodes ] );
    my $new_results_hash = node_list_to_hash( [ $new_xml_results->childNodes ] );

    #     print "old:\n";
    #     print Dumper($old_results_hash);
    #     print "new:\n";
    #     print Dumper($new_results_hash);

    my $new_results_keys = [ sort keys %{ $new_results_hash } ];
    my $old_results_keys = [ sort keys %{ $old_results_hash } ];

    if ( $_debug_mode )
    {
        my $comp = Array::Compare->new;

        my $comp_result = $comp->full_compare( $new_results_keys, $old_results_keys );

        my @comp_diffs = $comp->full_compare( $new_results_keys, $old_results_keys );

        if ( $comp_result )
        {
            print "new_results " . Dumper( $new_results_keys );
            print "old_results " . Dumper( $old_results_keys );
            print "diffs= " . Dumper( \@comp_diffs );
            print Dumper( @{ $old_results_keys }[ @comp_diffs ] );
            print Dumper( @{ $new_results_keys }[ @comp_diffs ] );

            #exit;
        }
    }

    foreach my $key ( @$new_results_keys )
    {
        if ( $old_results_hash->{ $key } )
        {
            $ret->{ $key } = $new_results_hash->{ $key } - $old_results_hash->{ $key };
        }
        else
        {
            $ret->{ $key } = 'N/A';
        }
    }

    #     print "delta:\n";
    #     print Dumper($ret);

    return $ret;
}

sub delta_row_to_string
{
    my ( $results_delta, $columns ) = @_;

    return map { $results_delta->{ $_ } } @$columns;
}

sub column_filter
{
    my ( $value, $exclude_pattern, $require_pattern ) = @_;

    return 1 if ( $value eq '_hours' );

    return 0 if ( defined( $exclude_pattern ) && ( $value =~ /$exclude_pattern/ ) );

    return 0 if ( defined( $require_pattern ) && ( $value !~ /$require_pattern/ ) );

    return 1;
}

sub delta_row_header
{
    my ( $results_delta, $exclude_pattern, $require_pattern ) = @_;

    return sort grep { column_filter( $_, $exclude_pattern, $require_pattern ) } ( keys %{ $results_delta } );
}

sub make_table
{
    my $latest_results      = shift;
    my $sorted_results_list = shift;
    my $exclude_pattern     = shift;
    my $require_pattern     = shift;

    my $table = Text::Table->new;

    my $first = 1;

    foreach my $results ( @$sorted_results_list )
    {
        my $results_delta = generate_results_delta( $latest_results, $results );
        if ( $first )
        {
            $table->add( delta_row_header( $results_delta, $exclude_pattern, $require_pattern ) );
            $first = 0;
        }
        $table->add(
            delta_row_to_string(
                $results_delta, [ delta_row_header( $results_delta, $exclude_pattern, $require_pattern ) ]
            )
        );
    }
    return $table;
}

sub make_new_url_found_percent_table
{
    my $latest_results      = shift;
    my $sorted_results_list = shift;
    my $exclude_pattern     = shift;
    my $require_pattern     = shift;

    my $table = Text::Table->new;

    my $first = 1;

    foreach my $results ( @$sorted_results_list )
    {

        my $row = {};

        #Grab the necessary information from the $results delta do this in a block so that the variables
        #don't live in scope longer than necessary.
        {
            my $results_delta = generate_results_delta( $latest_results, $results );
            if (   defined( $results_delta->{ found_urls_new } )
                && defined( $results_delta->{ found_urls_old } )
                && ( $results_delta->{ found_urls_new } ne 'N/A' )
                && ( $results_delta->{ found_urls_old } ne 'N/A' ) )
            {
                $row->{ found_percentage } =
                  $results_delta->{ found_urls_old } /
                  ( $results_delta->{ found_urls_new } + $results_delta->{ found_urls_old } ) * 100.0;
            }
            else
            {
                $row->{ found_percentage } = "N/A";
            }
            $row->{ _hours } = $results_delta->{ _hours };
        }

        #Grab the found_url_ratio value and convert it to a percent
        #We want the value not the delta so we need to reach into the XML object to get it
        my $node_list = ( ( %$results )[ 1 ] )->childNodes;
        my $ratio = node_list_to_hash( $node_list )->{ found_url_ratio };
        if ( defined $ratio )
        {
            $row->{ historical_percent_found } = ( $ratio * 100 ) / ( $ratio * 100 + 100 ) * 100;
        }

        #GRRR want to replace with a perl 5.10 //
        if ( !defined( $row->{ historical_percent_found } ) )
        {
            $row->{ historical_percent_found } = 'N/A';
        }

        if ( $first )
        {
            $table->add( delta_row_header( $row, $exclude_pattern, $require_pattern ) );
            $first = 0;
        }
        $table->add( delta_row_to_string( $row, [ delta_row_header( $row, $exclude_pattern, $require_pattern ) ] ) );
    }
    return $table;
}

sub main
{

    my $xml_file_name = shift( @ARGV );

    #print "$xml_file_name\n";

    die "Must specify file name" unless $xml_file_name;

    my $doc;

    my $historical_results;

    open( my $fh, '<', $xml_file_name ) || die "Could not open file $xml_file_name:$@";

    binmode $fh;    # drop all PerlIO layers possibly created by a use open pragma
    my $parser = XML::LibXML->new;
    $doc = $parser->parse_fh( $fh );
    close $fh;

    $historical_results = $doc->documentElement() || die;

    my @results_list = $historical_results->findnodes( "//results" )->get_nodelist();

    my @sorted_results_list = reverse sort { ( %{ $a } )[ 0 ] <=> ( %{ $b } )[ 0 ] } map {
        { $_->getAttribute( "time" ) => $_ }
    } @results_list;

    my $latest_results = shift @sorted_results_list;

    #print Dumper($latest_results);
    #print Dumper([@sorted_results_list]);
    my $table = make_table( $latest_results, \@sorted_results_list, 'found_blogs' );
    print "Past database status deltas:\n";
    print $table->table();

    $table = make_table( $latest_results, \@sorted_results_list, undef, 'found_blogs' );
    print "Found blog deltas:\n";
    print $table->table();

    $table = make_new_url_found_percent_table( $latest_results, \@sorted_results_list, undef, undef );
    print "Found url percent:\n";
    print $table->table();
}

main();
