#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use Text::CSV_XS;

use MediaWords::DB;

# get a hashref of nan codes from the csv
sub get_nan_codes_from_csv
{
    my ( $file ) = @_;

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "error using CSV_XS: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    $csv->column_names( $csv->getline( $fh ) );

    my $nan_codes = $csv->getline_hr_all( $fh );

    die( "no rows found in csv" ) unless ( $nan_codes && @{ $nan_codes } );

    die( "no url column in csv" ) unless ( $nan_codes->[ 0 ]->{ url } );

    return $nan_codes;
}

# get a list of the names of all fields that are actual codes and not just nan context / cruft
sub get_code_fields
{
    my ( $nan_codes ) = @_;

    my $nan_code = $nan_codes->[ 0 ];

    my $fields = [ keys( %{ $nan_code } ) ];

    my $code_fields = [];
    for my $field ( @{ $fields } )
    {
        if ( !grep { $field eq $_ } qw(user_id user_name code_id url date_saved) )
        {
            push( @{ $code_fields }, $field );
        }
    }

    return $code_fields;
}

# add nan codes to the controversy_media_codes
sub add_codes_to_media
{
    my ( $db, $controversy, $nan_codes ) = @_;

    my $code_fields = get_code_fields( $nan_codes );

    for my $nan_code ( @{ $nan_codes } )
    {
        my $medium = $db->query( "select * from media where url = ?", $nan_code->{ url } )->hash
          || die( "Unable to find medium '$nan_code->{ url }'" );

        for my $code_field ( @{ $code_fields } )
        {
            $db->query(
                "delete from controversy_media_codes where controversies_id = ? and media_id = ? and code_type = ?",
                $controversy->{ controversies_id },
                $medium->{ media_id }, $code_field
            );
            $db->query(
                "insert into controversy_media_codes ( controversies_id, media_id, code_type, code ) values ( ?, ?, ?, ? )",
                $controversy->{ controversies_id },
                $medium->{ media_id },
                $code_field, $nan_code->{ $code_field }
            );
            print STDERR "add $medium->{ name } $code_field: $nan_code->{ $code_field }\n";
        }
    }
}

sub main
{
    my ( $controversy_name, $file ) = @ARGV;

    die( "usage: $0 <controversy name> <csv file>" ) unless ( $controversy_name && $file );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->query( "select * from controversies where name = ?", $controversy_name )->hash
      || die( "Unable to find controversy '$controversy_name'" );

    my $nan_codes = get_nan_codes_from_csv( $file );

    add_codes_to_media( $db, $controversy, $nan_codes );
}

main();
