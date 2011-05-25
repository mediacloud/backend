package MediaWords::Util::CSV;

use strict;

use Encode;
use Text::CSV_XS;

# various functions for outputting csv

# return an encoded csv file representing a list of hashes
sub get_hashes_as_encoded_csv
{
    my ( $hashes ) = @_;
    
    my $output = '';
    if ( @{ $hashes } )
    {
        my $csv = Text::CSV_XS->new;

        my $keys = [ keys( %{ $hashes->[ 0 ] } ) ];
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

# send a list of hashes as a csv page through catalyst
sub send_hashes_as_csv_page
{
    my ( $c, $hashes, $title ) = @_;

    my $encoded_output = get_hashes_as_encoded_csv( $hashes );
    
    $c->res->header( 'Content-Disposition', qq[attachment; filename="$title"] );
    $c->res->header( 'Content-Length', length( $encoded_output ) );
    $c->res->content_type( 'text/csv' );
    $c->res->body( $encoded_output );
}

1;