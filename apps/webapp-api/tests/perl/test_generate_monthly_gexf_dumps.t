use strict;
use warnings;

use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::TM::Snapshot::GEXF;
use MediaWords::Test::DB::Create;

sub test_generate_monthly_dumps()
{
    my $db = MediaWords::DB::connect_to_db();

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'foo' );
   
    my $topics_id = $topic->{ topics_id };

    my $date = '2020-01-01';

    my $snapshot = $db->query( <<SQL,
        INSERT INTO snapshots (topics_id, snapshot_date, start_date, end_date)
        VALUES ( \$1, \$2, \$2, \$2 )
        RETURNING *
SQL
        $topic->{ topics_id }, $date
    )->hash;

    $db->query( <<SQL,
        INSERT INTO timespans (
            topics_id,
            snapshots_id,
            start_date,
            end_date,
            period,
            story_count,
            story_link_count,
            medium_count,
            medium_link_count,
            post_count,
            foci_id
        ) VALUES
            (\$1, \$2, \$3, \$3, 'overall', 0, 0, 0, 0, 0, null),
            (\$1, \$2, \$3, \$3, 'weekly', 0, 0, 0, 0, 0, null),
            (\$1, \$2, \$3, \$3, 'monthly', 0, 0, 0, 0, 0, null)
SQL
        $topic->{ topics_id }, $snapshot->{ snapshots_id }, $date
    );

    chdir( '/tmp' );

    MediaWords::TM::Snapshot::GEXF::generate_monthly_gexfs( $db, [ $topic->{ topics_id } ] );

    for my $period ( qw/overall monthly/ )
    {
        my $filename = "topic_${ topics_id }_${ period }_${ date }.gexf";
        ok( -f $filename, "dump exists: $filename" );
    }
}

sub main
{
    test_generate_monthly_dumps();

    done_testing();
}

main()
