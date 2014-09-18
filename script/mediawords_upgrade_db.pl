#!/usr/bin/env perl
#
# Concatenate and echo the database schema diff that would upgrade the Media Cloud
# database to the latest schema version (no --import parameter).
#  *or*
# Upgrade the Media Cloud database to the latest schema version (--import parameter).
#
# Usage: ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl > schema-diff.sql
#    or: ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl --import

use strict;
use warnings;

BEGIN
{
    my $source_rt;

    BEGIN
    {
        use File::Basename;
        use File::Spec;
        use Cwd qw( realpath );

        my $file_dir = dirname( __FILE__ );

        $source_rt = "$file_dir" . "/..";
        $source_rt = realpath( File::Spec->canonpath( $source_rt ) );
    }
    use lib "$source_rt/lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Getopt::Long;
use MediaWords::Pg::Schema;

sub main
{
    my $import   = 0;       # script should import the diff directly instead of echoing it out
    my $db_label = undef;

    my Readonly $usage = "Usage: $0 [ --db_label <label> ] > schema-diff.sql\n   or: $0 [ --db_label <label> ] --import";

    GetOptions( 'import' => \$import, 'db_label=s' => \$db_label ) or die "$usage\n";

    say STDERR ( $import ? 'Upgrading...' : 'Printing SQL statements for upgrade to STDOUT...' );
    eval { MediaWords::Pg::Schema::upgrade_db( $db_label, ( !$import ) ); };
    if ( $@ )
    {
        die "Error while upgrading: $@";
    }
    say STDERR "Done.";
}

main();
