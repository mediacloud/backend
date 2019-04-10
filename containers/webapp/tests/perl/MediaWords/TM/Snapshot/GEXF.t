#!/usr/bin/env prove

use strict;
use warnings;

use Test::Deep;
use Test::More;

use MediaWords::CommonLibs;

use MediaWords::TM::Snapshot::GEXF;

sub test_trim_to_giant_component
{
    my $media_links = [
        { source => 1, target => 2 },
        { source => 1, target => 3 },
        { source => 2, target => 3 },
        { source => 4, target => 5 }
    ];

    my $expected_links = [ { source => 1, target => 2 }, { source => 1, target => 3 }, { source => 2, target => 3 } ];

    my $got_links = MediaWords::TM::Snapshot::GEXF::_trim_to_giant_component( $media_links );
    cmp_deeply( $got_links, $expected_links, "trimmed links" );
}

sub main
{
    test_trim_to_giant_component();

    done_testing();
}

main()
