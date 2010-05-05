#!/usr/bin/perl

# add plperl functions to database.

# see MediaWords::Pg::Schema for definition of which functions to add

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::Pg::Schema;

sub main
{
    my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);
    
    MediaWords::Pg::Schema::add_functions( $db );
}

main();
