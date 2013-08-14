#!/usr/bin/env perl

# import a set of medium -> controversy_media_codes mappings from a csv

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Getopt::Long;
use Text::CSV_XS;

use MediaWords::DB;
use MediaWords::DBI::Controversies;

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

# lookup the medium in the controversy by id, name, or url
sub get_medium_from_csv_code
{
    my ( $db, $controversy, $csv_code ) = @_;

    my $cc = $csv_code;

    my $media =
      $db->query( <<END, $controversy->{ controversies_id }, $cc->{ media_id }, $cc->{ name }, $cc->{ url } )->hashes;
select distinct m.* 
    from media m
        join stories s on ( s.media_id = m.media_id )
        join controversy_stories cs on ( cs.stories_id = s.stories_id and cs.controversies_id = ? )
    where 
        m.dup_media_id is null and
            ( m.media_id = ? or
                m.name = ? or
                m.url = ? )
END

    if ( !$media )
    {
        print STDERR "Unable to find medium for csv_code: " . Dumper( $csv_code ) . "\n";
        return undef;
    }

    if ( @{ $media } > 1 )
    {
        print STDERR "Found more than one medium for csv_code: " . Dumper( $csv_code ) . "\n" . Dumper( $media ) . "\n";
        return undef;
    }

    return $media->[ 0 ];
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

    # print STDERR "add $medium->{ name } $code_type: $csv_code->{ code }\n";
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

    my $controversies = MediaWords::DBI::Controversies::require_controversies_by_opt( $db, $controversy_opt );

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
