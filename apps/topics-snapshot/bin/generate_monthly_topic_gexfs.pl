#!/usr/bin/env perl

# generate overall and monthly gexfs for a topic, eliminating some large platform media sources

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use File::Slurp;

use MediaWords::TM::Snapshot;
use MediaWords::TM::CLI;

Readonly my $EXCLUDE_MEDIA_IDS =>
  [ 18362, 18346, 18370, 61164, 269331, 73449, 62926, 21936, 5816, 4429, 20448, 67324, 351789, 22299, 135076, 25373 ];

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $topics = MediaWords::TM::CLI::require_topics_by_opt( $db );

    for my $topic ( @{ $topics } )
    {
        my $overall_timespan = MediaWords::TM::get_latest_overall_timespan( $db, $topic->{ topics_id } );

        my $monthly_timespans = $db->query( <<SQL, $overall_timespan->{ snapshots_id } )->hashes;
select * from timespans where snapshots_id = \$1 and period = 'monthly' and foci_id is null order by start_date asc
SQL

        for my $timespan ( $overall_timespan, @{ $monthly_timespans } )
        {

            DEBUG( "generating timespan $timespan->{ period } $timespan->{ start_date } ..." );

            MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan );

            my $gexf = MediaWords::TM::Snapshot::get_gexf_snapshot(
                $db,
                $timespan,
                {
                    max_media         => 100_000,
                    exclude_media_ids => $EXCLUDE_MEDIA_IDS,
                    color_field       => 'partisan_retweet',
                    include_weights   => 1
                }
            );

            MediaWords::TM::Snapshot::discard_temp_tables( $db );

            my $topics_id = $topic->{ topics_id };
            my $period    = $timespan->{ period };
            my $date      = substr( $timespan->{ start_date }, 0, 10 );
            $date =~ s/\-//g;

            my $filename = "topic_${ topics_id }_${ period }_${ date }.gexf";

            File::Slurp::write_file( $filename, encode_utf8( $gexf ) );
        }
    }
}

main();

#     my $twitter_media_ids = $db->query( <<SQL )->flat;
# (
#     select media_id
#         from snap.medium_link_counts mlc
#         where
#             mlc.timespans_id = 70638
#         order by mlc.simple_tweet_count desc
#         limit 50
# )
# union
# (
#     select media_id
#         from snap.medium_link_counts mlc
#         where
#             mlc.timespans_id = 70638
#         order by mlc.facebook_share_count desc
#         limit 50
# )
# SQL
#
#     my $extra_data = $db->query( <<SQL )->hashes;
# select mlc.media_id, mlc.facebook_share_count tw_facebook_share_count, mlc.simple_tweet_count tw_simple_tweet_count
#     from snap.medium_link_counts mlc
#     where mlc.timespans_id = 70638
# SQL

__END__
