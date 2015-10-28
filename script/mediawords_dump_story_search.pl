#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::CM::DumpControversy job
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Solr;
use MediaWords::Util::CSV;

sub main
{
    my ( $q ) = @ARGV;

    die( "usage: $0 <query>" ) unless ( $q );

    my $db = MediaWords::DB::connect_to_db;

    my $stories = MediaWords::Solr::search_for_stories( $db, { q => $q, sort => 'random_1 asc', rows => 200 } );

    # use Data::Dumper;
    # print Dumper( res );

    print MediaWords::Util::CSV::get_hashes_as_encoded_csv( $stories );
}

main();

__END__
