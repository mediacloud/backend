package MediaWords::Util::JSON;
use MediaWords::CommonLibs;


# very simple module for generating from perl data

use strict;

# return a json string representing a perl data structre
sub get_json_from_perl
{
    my ( $data ) = @_;
    
    if ( ref( $data ) eq 'ARRAY' )
    {
        return "[\n" . join( ",\n", map { get_json_from_perl( $_ ) } @{ $data } ) . "]\n";
    }
    elsif( ref( $data ) eq 'HASH' )
    {
        return "{\n" . join( ",\n", map { "$_: " . get_json_from_perl( $data->{ $_ } ) } keys( %{ $data } ) ) . "}\n";
    }
    else {
        return "''" if ( !defined( $data ) );
        
        if ( $data =~ /^[0-9]+$/ )
        {
            return $data;
        }
        else {
            $data =~ s/'/\\'/g;
            return "'$data'";
        }
    }
}

1;