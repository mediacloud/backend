package MediaWords::Util::CSV;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use Text::CSV_XS;

# various functions for outputting csv

# return an encoded csv file representing a list of hashes.
# if $fields is specified, use it as a list of field names and
# snapshot the fields in the specified order.  otherwise, just
# get the field names from the hash in the first row (with
# semi-random order)
sub get_hashes_as_encoded_csv
{
    my ( $hashes, $fields ) = @_;

    my $output = '';
    if ( @{ $hashes } )
    {
        my $csv = Text::CSV_XS->new( { binary => 1 } );

        my $keys = $fields || [ keys( %{ $hashes->[ 0 ] } ) ];
        $csv->combine( @{ $keys } );

        $output .= $csv->string . "\n";

        for my $hash ( @{ $hashes } )
        {
            $csv->combine( map { $hash->{ $_ } } @{ $keys } );

            $output .= $csv->string . "\n";
        }
    }

    my $encoded_output = Encode::encode( 'utf-8', $output );

    return $encoded_output;
}

# Given a database handle and a query string and some parameters, execute the query with the parameters
# and return the results as a csv with the fields in the query order
sub get_query_as_csv
{
    my ( $db, $query, @params ) = @_;

    my $res = $db->query( $query, @params );

    my $fields = $res->columns;

    my $data = $res->hashes;

    my $csv_string = get_hashes_as_encoded_csv( $data, $fields );

    return $csv_string;
}

1;
