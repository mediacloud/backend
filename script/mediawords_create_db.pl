#!/usr/bin/env perl
#
# See MediaWords::Pg::Schema for definition of which functions to add
#
# Set the MEDIAWORDS_CREATE_DB_DO_NOT_CONFIRM=1 environment variable to create
# the database without confirming the action.
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Pg::Schema;

use Term::Prompt;
use Readonly;

Readonly my $MAX_STORIES => 1000;

sub too_many_stories
{
    my $db = MediaWords::DB::connect_to_db;

    my ( $stories_exists ) = $db->query( "select 1 from pg_class where relname = 'stories'" )->flat;

    return 0 unless ( $stories_exists );

    my ( $num_stories ) = $db->query( "select count(*) from ( select 1 from stories limit ? ) q", $MAX_STORIES )->flat;

    return ( $num_stories >= $MAX_STORIES ) ? 1 : 0;
}

sub main
{
    if ( too_many_stories() )
    {
        say "Refusing to drop database with at least $MAX_STORIES stories";
        return 1;
    }

    my $continue_and_reset_db;
    unless ( defined $ENV{ 'MEDIAWORDS_CREATE_DB_DO_NOT_CONFIRM' } )
    {
        my $warning_message = <<EOF;

Warning: this script will delete all information in the current
Media Cloud database and create a new database.

Are you sure you wish to continue?

EOF
        $Term::Prompt::MULTILINE_INDENT = '';
        $continue_and_reset_db = &prompt( "y", $warning_message, "", "n" );
    }
    else
    {
        $continue_and_reset_db = 1;
    }

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
        say "Database creation successful.";
        say '';
    }
}

main();
