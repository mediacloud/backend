package MediaWords::Util::SchemaVersion;

# Utility function to determine a database schema version from a bunch of SQL commands

# Does a trivial thing, so the usual Media Cloud Perl file header is omitted.

use strict;
use warnings;

sub schema_version_from_lines
{
    my @input = @_; # a bunch of SQL strings

    foreach ( @input )
    {
        if ( $_ =~ /MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT/ )
        {
            s/[\+\-]*\s*MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := (\d+?);/$1/;
            die "Unable to parse the database schema version number.\n" unless $_;
            return $_+0;
        }
    }

    # Err at this point (the 'foreach' above should have returned already)
    return 0;
}

1;
