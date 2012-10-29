#!/usr/bin/env perl
#
# Upgrade the Media Cloud database to use the latest Media Cloud schema version.
#
# Usage: ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::Pg::Schema;

use Term::Prompt;

sub main
{
    my $warning_message = <<EOF;
WARNING: this script will try to upgrade the current Media Cloud database
to the newest schema version. Make sure you have a reliable backup of the
database before continuing. Are you sure you wish to continue?
EOF
    $warning_message =~ s/^\s+//;
    $warning_message =~ s/\s+$//;
    $warning_message =~ s/\n/ /g;

    my $continue_and_reset_db = &prompt( 'y', $warning_message, '', 'n' );

    exit if !$continue_and_reset_db;

    my $result = MediaWords::Pg::Schema::upgrade_db();

    if ( $result )
    {
        say '';
        say 'WARNING:';
        say 'Error while trying to upgrade database schema.';
    }
    else
    {
        say '';
        say '';
        say '';
        say 'Database upgrade was successful.';
        say '';
    }
}

main();
