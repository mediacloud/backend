#!/usr/bin/perl -w

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use XML::LibXML;
use Getopt::Long;
use Readonly;
use Carp;
use MIME::Base64;
use Try::Tiny;
use MediaWords::Util::DatabaseRestore;

sub main
{

    my Readonly $usage =
'USAGE: ./mediawords_restore_table_with_awk.pl --table_name foo --sql_dump_file dump_file --line_number_file file --database_name dbName ';

    my ( $table_name, $sql_dump_file, $line_number_file, $db_name );

    GetOptions(
        'table_name=s'       => \$table_name,
        'sql_dump_file=s'    => \$sql_dump_file,
        'line_number_file=s' => \$line_number_file,
        'database_name=s'    => \$db_name,
    ) or die "$usage\n";

    die "$usage\n"
      unless $table_name && $sql_dump_file && $line_number_file && $db_name;

    MediaWords::Util::DatabaseRestore::test_opening_files( $line_number_file, $sql_dump_file );

    #say STDERR Dumper( [ $table_name, $sql_dump_file, $line_number_file ] );

    say STDERR "starting -- $table_name " . localtime();

    my $start_and_end_lines =
      MediaWords::Util::DatabaseRestore::get_start_and_end_line_for_table( $line_number_file, $table_name );

    my $start_line = $start_and_end_lines->{ start_line };
    my $end_line   = $start_and_end_lines->{ end_line };

    say STDERR "start line: $start_line, end line: $end_line ";

    my $awk_command =
      " nawk 'NR>= $start_line && NR <= $end_line { print  }' $sql_dump_file | psql --single-transaction -d $db_name ";

    say STDERR "Running awk_command for table '$table_name': $awk_command";

    system( $awk_command ) && die "Error running $awk_command: '$@'";

    say STDERR "Finished '$awk_command' for $table_name";

}

main();
