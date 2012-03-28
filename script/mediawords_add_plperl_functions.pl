#!/usr/bin/env perl

# add plperl functions to database.

# see MediaWords::Pg::Schema for definition of which functions to add

# usage: mediawords_add_plperl_functions.pl [-p]
#
# -p: only print, do not execute sql function definitions

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::CommonLibs;

use MediaWords::Pg::Schema;

sub main
{
    if ( $ARGV[ 0 ] eq '-p' )
    {
        print MediaWords::Pg::Schema::get_sql_function_definitions . "\n";
    }
    else
    {
        my $db = MediaWords::DB::connect_to_db();
        MediaWords::Pg::Schema::add_functions( $db );
    }
}

main();
