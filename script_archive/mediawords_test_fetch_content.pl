#!/usr/bin/perl

# retrieve and display the content from ten downloads to verify that content fetching is working

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::DBI::Downloads;

sub main
{

    my $db = MediaWords::DB::connect_to_db();

    my $downloads = $db->query(
        "select * from downloads where state = 'success' and type = 'content' " . "  order by downloads_id desc limit 10" )
      ->hashes;

    for my $d ( @{ $downloads } )
    {
        my $content_ref = MediaWords::DBI::Downloads::fetch_content( $d );

        print "$d->{url} [$d->{downloads_id}]:\n";
        print "****\n";
        print $$content_ref . "\n";
        print "****\n";
    }
}

main();
