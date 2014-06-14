package MediaWords::Test::Data;

# store and fetch testing data

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Data::Dumper;

# get the file path corresponding to the given key
sub _get_data_file
{
    my ( $key ) = @_;

    if ( $key =~ /[^a-z0-9_]/i )
    {
        die( "data key can only include /[a-z0-9_]/i" );
    }

    return "$FindBin::Bin/../t/data/$key.pl";
}

# write the given data to disk under the given key
sub store_test_data
{
    my ( $key, $data ) = @_;

    my $file = _get_data_file( $key );

    if ( !open( FILE, ">$file" ) )
    {
        die( "Unable to open file $file: $!" );
    }

    print FILE "#<<<\n";
    print FILE Dumper( $data );
    print FILE "#>>>\n";

    close( FILE );
}

# fetch the given data from disk
sub fetch_test_data
{
    my ( $key ) = @_;

    my $file = _get_data_file( $key );

    if ( !open( FILE, "<$file" ) )
    {
        die( "Unable to open file $file: $!" );
    }

    my $data;
    while ( my $line = <FILE> )
    {
        $data .= $line;
    }

    close( FILE );

    my $VAR1;
    eval( $data );
    if ( $@ )
    {
        die( "error restoring data: $@" );
    }

    return $VAR1;
}

1;
