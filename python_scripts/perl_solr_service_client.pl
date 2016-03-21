#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Thrift::SolrFacets;

use Data::Dumper;

eval {
    my $q           = 'sentence:"birth control"';
    my $facet_field = 'media_id';
    my $fq          = [];
    my $mincount    = 1;

    my $counts = MediaWords::Thrift::SolrFacets::get_media_counts( $q, $facet_field, $fq, $mincount );

    say Dumper( $counts );

    $fq = [ 'media_id:1' ];

    $counts = MediaWords::Thrift::SolrFacets::get_media_counts( $q, $facet_field, $fq, $mincount );

    say Dumper( $counts );

};

if ( $@ )
{
    warn( Dumper( $@ ) );
}
