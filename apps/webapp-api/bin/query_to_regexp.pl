#!/usr/bin/env perl

# convert solr query to regular expression

use strict;
use warnings;

use MediaWords::Solr::Query::Parse;

sub main
{
    my ( $query ) = @ARGV;

    binmode( STDOUT, ':utf8' );

    my $regex = MediaWords::Solr::Query::Parse::parse_solr_query( $query )->re();

    print "$regex\n";
}

main();
