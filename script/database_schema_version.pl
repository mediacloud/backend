#!/usr/bin/env perl
#
# Return schema version from the SQL file
#
# Usage:
# ./script/database_schema_version.pl ./schema/mediawords.sql
# or
# cat ./schema/mediawords.sql | ./script/database_schema_version.pl -

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use File::Slurp;

use MediaWords::DB::Schema::Version;

sub main
{
    my $usage =
      "Usage:\n" .
      "    ./script/run_with_carton.sh ./script/database_schema_version.pl ./schema/mediawords.sql # read from file\n" .
      "or\n" .
"    cat ./schema/mediawords.sql | ./script/run_with_carton.sh ./script/database_schema_version.pl - # read from STDIN\n";

    die $usage unless $#ARGV == 0;    # 1 argument
    my $sql_filename = $ARGV[ -1 ];

    my $sql;
    if ( $sql_filename eq '-' )
    {
        $sql = do { local $/; <STDIN> };
    }
    else
    {
        $sql = read_file( $sql_filename );
    }

    my $schema_version = MediaWords::DB::Schema::Version::schema_version_from_lines( $sql );
    die "Unable to determine schema version.\n" unless ( $schema_version );

    print $schema_version;
}

main();
