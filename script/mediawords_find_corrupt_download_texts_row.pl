#!/usr/bin/perl

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


sub main
{
    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    my $offset = 0;
    my $limit  = 5000;
    while ( $db->query( "select * from download_texts limit $limit offset $offset" )->rows )
    {
        $offset += $limit;
        print "offset: $offset\n";
    }
}

main();
