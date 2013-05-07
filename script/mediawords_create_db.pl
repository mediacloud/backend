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

use constant MAX_STORIES => 1000;

sub too_many_stories
{
    my $db = MediaWords::DB::connect_to_db;

    my ( $stories_exists ) = $db->query( "select 1 from pg_class where relname = 'stories'" )->flat;

    return 0 unless ( $stories_exists );

    my ( $num_stories ) = $db->query( "select count(*) from ( select 1 from stories limit ? ) q", MAX_STORIES )->flat;

    return ( $num_stories >= MAX_STORIES ) ? 1 : 0;
}

sub main
{
    if ( too_many_stories() )
    {
        say "Refusing to drop database with at least " . MAX_STORIES . " stories";
        return 1;
    }

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
        say "Database creation successful.";
        say '';
    }
}

main();
