#!/usr/bin/env perl

# convert solr query to regular expression

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Parse::BooleanLogic;

# convert a single search term to a regular expression
sub convert_term_to_regex
{
    my ( $term ) = @_;

    $term =~ s/"//g;
    $term =~ s/\*/\.\*/g;
    $term =~ s/ /\[\[\:space\:\]\]\+/g;

    if ( $term !~ /\w/ )
    {
        die( "non-alnum character in term: '$term'" );
    }

    return $term;
}

# recurse down the tree, converting search query to regular expression as we go
# $VAR1 = [
#           [
#             {
#               'operand' => 'foo'
#             },
#             'or',
#             {
#               'operand' => 'bar'
#             }
#           ],
#           'and',
#           {
#             'operand' => 'baz'
#           }
#         ];
sub convert_tree_to_regex
{
    my ( $tree ) = @_;

    die( "tree must be a list or array" ) unless ( ref( $tree ) );
    if ( ref( $tree ) eq 'HASH' )
    {
        die( "expecting operand" ) unless ( $tree->{ operand } );
        return convert_term_to_regex( $tree->{ operand } );
    }
    elsif ( ref( $tree ) eq 'ARRAY' )
    {
        if ( ( scalar( @{ $tree } ) % 2 ) == 0 )
        {
            die( "tree must have odd number of members:\n" . Dumper( $tree ) );
        }
        elsif ( scalar( @{ $tree } ) > 3 )
        {
            my $a  = shift( @{ $tree } );
            my $op = shift( @{ $tree } );

            return convert_tree_to_regex( [ $a, $op, $tree ] );
        }
        elsif ( scalar( @{ $tree } ) == 3 )
        {
            my $a  = convert_tree_to_regex( $tree->[ 0 ] );
            my $op = lc( $tree->[ 1 ] );
            my $b  = convert_tree_to_regex( $tree->[ 2 ] );

            if ( $op eq 'and' )
            {
                return "(?: (?: $a .* $b ) | (?: $b .* $a ) )";
            }
            elsif ( $op eq 'or' )
            {
                return "(?: $a | $b )";
            }
            else
            {
                die( "unknown operator '$op'" );
            }
        }
        elsif ( scalar( @{ $tree } ) == 1 )
        {
            return convert_tree_to_regex( $tree->[ 0 ] );
        }
        else
        {
            die( "can't get here because we already checked whether tree has odd number of members" );
        }
    }
    else
    {
        die( "Unknown ref type:\n" . Dumper( $tree ) );
    }
}

sub main
{
    my ( $q ) = @ARGV;

    die( "usage: $0 <q>" ) unless ( $q );

    my $parser = Parse::BooleanLogic->new();

    my $tree = $parser->as_array( $q );

    my $regex = convert_tree_to_regex( $tree );

    print "$regex\n";
}

main();
