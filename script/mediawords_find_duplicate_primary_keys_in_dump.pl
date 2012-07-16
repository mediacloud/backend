#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;
use MediaWords::Util::DatabaseRestore;
use Getopt::Long;

sub main
{
    my Readonly $usage =
      'USAGE: ./mediawords_find_duplicate_primary_keys_in_dump.pl --table_name foo --sql_dump_file dump_file --byte_offset_file file ';

    my ( $table_name, $sql_dump_file, $byte_offset_file );

    GetOptions(
        'table_name=s'       => \$table_name,
        'sql_dump_file=s'    => \$sql_dump_file,
        'byte_offset_file=s' => \$byte_offset_file
    ) or die "$usage\n";

    die "$usage\n"
      unless $table_name && $sql_dump_file && $byte_offset_file;

    MediaWords::Util::DatabaseRestore::test_opening_files( $byte_offset_file, $sql_dump_file );

    #say STDERR Dumper( [ $table_name, $sql_dump_file, $byte_offset_file ] );

    say STDERR "starting --  " . localtime();

    #This function just parse grep output so despite its name it doesn't care if the thing to the left of the ':' is a byte offset or line number
    my $start_and_end_bytes =
      MediaWords::Util::DatabaseRestore::get_start_and_end_line_for_table( $byte_offset_file, $table_name );

    my $start_byte = $start_and_end_bytes->{ start_line };
    my $end_byte  = $start_and_end_bytes->{ end_line };

    open ( my $sql_file, '<', $sql_dump_file );

    seek( $sql_file, $start_byte, 0 );

    say STDERR "reading data until copy statement";

    my $lines_until_copy = 0;
    MediaWords::Util::DatabaseRestore::read_until_copy_statement( $sql_file, $table_name, \$lines_until_copy );

    my $primary_keys = {};
    
    my $lines_read = 0;

    my $last_pos = tell( $sql_file);

    say STDERR "searching for duplicate keys";

    while ( my $line = <$sql_file> )
    {
	$lines_read++;

	if ( ($lines_read % 10000) == 0 )
	{
	    say STDERR "searched $lines_read line records";
	}

	#say "Read line:$line";

	$line =~ /^(\d+)\t/;

	exit if $line =~ /^\-\-/;

	my $key = $1;

	exit unless defined($key);

	#say "Primary key is '$key'";

	if ( !defined ( $primary_keys->{ $key } ) )
	{
	    $primary_keys->{ $key } = $last_pos;
	}
	else
	{
	    say "Duplicate primary key $key";

	    my $current_pos = tell( $sql_file );

	    my $old_pos =  $primary_keys->{ $key };

	    seek( $sql_file, $old_pos, 0 );

	    my $old_line = <$sql_file>;

	    seek( $sql_file, $current_pos, 0 );

	    say "line at $old_pos has the same primary key as line at $last_pos";
	    say "old line (byte offset $old_pos ): $old_line";
	    say "new line (byte offset $last_pos): $line";
	    
	    #exit;
	}

	$last_pos = tell( $sql_file );
	#say "New file position $last_pos";

	#exit if $lines_read >= 10;
    }
}

main();
