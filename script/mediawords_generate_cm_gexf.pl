#!/usr/bin/env perl

# generate gexf dump of network graph for the media in a controversy time slice

# usage mediawords_generate_cm_gexf.pl <cdts_id>

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::CommonLibs;
use Modern::Perl '2015';

use MediaWords::CM::Graph;
use MediaWords::DB;

sub main
{
    my ( $cdts_id ) = @ARGV;

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    die( "usage: $0 <cdts_id>" ) unless ( $cdts_id );

    my $db = MediaWords::DB::connect_to_db;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $cdts_id )
      || die( "unable to find time slice '$cdts_id'" );

    my $g = MediaWords::CM::Graph->new( db => $db, cdts_id => $cdts_id );
    $g->add_media_nodes_with_hyperlink_edges();
    $g->layout( 'media type' );

    my $gexf = $g->export_gexf();

    print $gexf;

}

main();
