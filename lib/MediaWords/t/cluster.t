use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../../lib";
    use lib "$FindBin::Bin/../../../t";
}

use Dir::Self;
use Data::Dumper;
use DBIx::Simple::MediaWords;
use MediaWords::Util::Tags;
use MediaWords::Test::DB;

#use Test::NoWarnings;
#use Test::More tests => 7;
use Test::More skip_all => "We need to set up a special database to actually test clustering";

use_ok( 'MediaWords::Cluster' );

sub get_cluster_run
{
    ( my $db, my $start_date, my $end_date, my $tag_name, my $description, my $num_clusters ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_tag( $db, $tag_name );
    if ( !$tag )
    {
        die "Unable to find tag $tag_name";
    }

    my $tags_id = $tag->{ tags_id };

    my $cluster_run_hash = {
        start_date   => $start_date,
        end_date     => $end_date,
        tags_id      => $tags_id,
        description  => $description,
        num_clusters => $num_clusters,
    };

    my $cluster_run = $db->create( 'media_cluster_runs', $cluster_run_hash );
    return $cluster_run;
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;

            my $start_date   = '2006-01-01';
            my $end_date     = '2011-01-01';
            my $tag_name     = 'content_type:news';
            my $description  = 'foo2';
            my $num_clusters = 2;

            my $cluster_run = get_cluster_run( $db, $start_date, $end_date, $tag_name, $description, $num_clusters );

            MediaWords::Cluster::execute_and_store_media_cluster_run( $db, $cluster_run );

            print "Completed cluster run\n";
        }
    );
}

main();

1;
