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

    my $result = MediaWords::Pg::Schema::get_is_stop_stem_function_tables_and_definition();

    say $result;

    exit;
}

main();
