#!/usr/bin/env perl

# add plperl functions to database.

# see MediaWords::Pg::Schema for definition of which functions to add

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
    my $warning_message =
"Warning this script will delete all information in the current media cloud database and create a new database. Are you sure you wish to continue?";

    my $continue_and_reset_db = &prompt( "y", $warning_message, "", "n" );

    exit if !$continue_and_reset_db;

    my $result = MediaWords::Pg::Schema::recreate_db();

    if ( $result )
    {
        say '';
        say "Warning:";
        say "Error creating database";
    }
    else
    {
        say '';
        say '';
        say '';
        say "Database creation successfull.";
        say '';
    }
}

main();
