#!/usr/bin/env perl
#
# Return schema version from the SQL file
#
# Usage:
# ./script/database_schema_version.pl ./script/mediawords.sql
# or
# cat ./script/mediawords.sql | ./script/database_schema_version.pl -

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::SchemaVersion;

sub main
{
    my $usage =
      "Usage:\n" .
      "    ./script/run_with_carton.sh ./script/database_schema_version.pl ./script/mediawords.sql # read from file\n" .
      "or\n" .
"    cat ./script/mediawords.sql | ./script/run_with_carton.sh ./script/database_schema_version.pl - # read from STDIN\n";

    die $usage unless $#ARGV == 0;    # 1 argument
    my $sql_filename = $ARGV[ -1 ];

    my @input;
    if ( $sql_filename eq '-' )
    {
        @input = <STDIN>;
    }
    else
    {
        open SQLFILE, $sql_filename or die $!;
        @input = <SQLFILE>;
        close SQLFILE;
    }

    my $schema_version = MediaWords::Util::SchemaVersion::schema_version_from_lines( @input );
    die "Unable to determine schema version.\n" unless ( $schema_version );

    print $schema_version;
}

main();
