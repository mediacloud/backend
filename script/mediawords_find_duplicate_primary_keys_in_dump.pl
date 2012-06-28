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

sub main
{
    my @ARGS = @ARGV;

    open ( my $sql_file, '<', '/tmp/media.sql' );

    my $start_byte = 899;

    seek( $sql_file, $start_byte, 0 );

    my $lines_until_copy = 0;
    MediaWords::Util::DatabaseRestore::read_until_copy_statement( $sql_file, 'media', \$lines_until_copy );

    my $primary_keys = {};
    

    my $lines_read = 0;

    my $last_pos = tell( $sql_file);

    while ( my $line = <$sql_file> )
    {
	$lines_read++;

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
