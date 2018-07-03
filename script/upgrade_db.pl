#!/usr/bin/env perl
#
# Concatenate and echo the database schema diff that would upgrade the Media Cloud
# database to the latest schema version (no --import parameter).
#  *or*
# Upgrade the Media Cloud database to the latest schema version (--import parameter).
#
# Usage: ./script/run_in_env.sh ./script/upgrade_db.pl > schema-diff.sql
#    or: ./script/run_in_env.sh ./script/upgrade_db.pl --import

use strict;
use warnings;

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use MediaWords::DB::Schema;

sub main
{
    my $import   = 0;       # script should import the diff directly instead of echoing it out
    my $db_label = undef;

    my Readonly $usage = "Usage: $0 [ --db_label <label> ] > schema-diff.sql\n   or: $0 [ --db_label <label> ] --import";

    GetOptions( 'import' => \$import, 'db_label=s' => \$db_label ) or die "$usage\n";

    DEBUG $import ? 'Upgrading...' : 'Printing SQL statements for upgrade to STDOUT...';
    eval { MediaWords::DB::Schema::upgrade_db( $db_label, ( !$import ) ); };
    if ( $@ )
    {
        die "Error while upgrading: $@";
    }
    DEBUG( "Done." );
}

main();
