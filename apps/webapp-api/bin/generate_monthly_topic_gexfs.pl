#!/usr/bin/env perl

# generate overall and monthly gexfs for a topic, eliminating some large platform media sources

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use File::Slurp;

use MediaWords::DB;
use MediaWords::TM::Snapshot::GEXF;
use MediaWords::TM::Snapshot::Views;

sub main 
{
    my $db = MediaWords::DB::connect_to_db();

    my $topics_ids = [ map { int( $_ ) } @ARGV ];

    MediaWords::TM::Snapshot::GEXF::generate_monthly_gexfs( $db, $topics_ids );
}


main();
