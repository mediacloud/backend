#!/usr/bin/env perl

# import a set of medium -> controversy_media_codes mappings from a csv

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Getopt::Long;
use Text::CSV_XS;

use MediaWords::DB;
use MediaWords::CM;

# hash of all media with stories in a controversy, hashed by media_id and controversies_id
my $_medium_controversy_lookup;

# get a list of hashes from the csv. validate that each row has a media_id or name field and a code field
sub get_csv_codes
{
    my ( $file ) = @_;

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "error using CSV_XS: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    $csv->column_names( $csv->getline( $fh ) );

    my $csv_codes = $csv->getline_hr_all( $fh );

    die( "no rows found in csv" ) unless ( $csv_codes && @{ $csv_codes } );

    die( "no url column in csv" ) unless ( grep { $csv_codes->[ 0 ]->{ $_ } } qw(url name media_id) );

    close( $fh );

    return $csv_codes;
}

# return a lookup table with every media source that is part of any controversy, hashed by media_id and controversies_id
sub get_medium_controversy_lookup
{
    my ( $db ) = @_;

    return $_medium_controversy_lookup if ( $_medium_controversy_lookup );

    my $media = $db->query( <<END )->hashes;
select distinct m.*, s.controversies_id
    from
        media m
        join cd.live_stories s on ( m.media_id = s.media_id )
END

    for my $medium ( @{ $media } )
    {
        $_medium_controversy_lookup->{ $medium->{ media_id } }->{ $medium->{ controversies_id } } = $medium;
    }

    return $_medium_controversy_lookup;
}

# lookup the medium in the controversy by id, name, or url
sub get_medium_from_csv_code
{
    my ( $db, $controversy, $csv_code ) = @_;

    my $lookup = get_medium_controversy_lookup( $db );

    return $lookup->{ $csv_code->{ media_id } }->{ $controversy->{ controversies_id } };
}

# add nan codes to the controversy_media_codes
sub add_codes_to_media
{
    my ( $db, $controversy, $code_type, $csv_code ) = @_;

    my $medium = get_medium_from_csv_code( $db, $controversy, $csv_code );
    return unless ( $medium );

    if ( $csv_code->{ code } && ( $csv_code->{ code } ne 'null' ) )
    {
        $db->query(
            "insert into controversy_media_codes ( controversies_id, media_id, code_type, code ) values ( ?, ?, ?, ? )",
            $controversy->{ controversies_id },
            $medium->{ media_id },
            $code_type, $csv_code->{ code }
        );
    }

    print STDERR "add $controversy->{ name }: $medium->{ name } $code_type = $csv_code->{ code }\n";
}

sub main
{
    my ( $controversy_opt, $code_type, $csv );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "controversy=s" => \$controversy_opt,
        "code_type=s"   => \$code_type,
        "csv=s"         => \$csv
    ) || return;

    die( "usage: $0 --controversy < controversies_id | pattern > --code_type < code type > --csv < csv file >" )
      unless ( $controversy_opt && $code_type && $csv );

    my $db = MediaWords::DB::connect_to_db;

    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );

    for my $controversy ( @{ $controversies } )
    {
        print STDERR "CONTROVERSY $controversy->{ name }\n";
        my $csv_codes = get_csv_codes( $csv );

        $db->query( <<END, $controversy->{ controversies_id }, $code_type );
delete from controversy_media_codes where controversies_id = ? and code_type = ?
END

        map { add_codes_to_media( $db, $controversy, $code_type, $_ ) } @{ $csv_codes };
    }
}

main();
