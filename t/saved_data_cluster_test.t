use strict;
use warnings;

# basic sanity test of crawler functionality

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More;
use Test::Differences;
use Test::Deep;

use MediaWords::Util::Graph;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::MediaSets;
use MediaWords::DBI::Stories;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use Perl6::Say;

sub main
{

    my ( $dump ) = @ARGV;

    my $nodes          = MediaWords::Test::Data::fetch_test_data( 'cluster_test_1_nodes' );
    my $media_clusters = MediaWords::Test::Data::fetch_test_data( 'cluster_test_1_media_clusters' );

    use_ok( 'MediaWords::Util::Graph' );

    MediaWords::Util::Graph::do_get_graph( $nodes, $media_clusters, 'graph-layout-aesthetic' );

    done_testing();
}

main();

