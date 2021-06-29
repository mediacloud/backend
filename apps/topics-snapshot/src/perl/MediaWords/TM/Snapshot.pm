package MediaWords::TM::Snapshot;

=head1 NAME

MediaWords::TM::Snapshot - Snapshot and analyze topic data

=head1 SYNOPSIS

    # generate a new topic snapshot -- this is run via snapshot_topic.pl once or each snapshot
    snapshot_topic( $db, $topics_id );

    # the rest of these examples are run each time we want to query topic data

    # setup and query snapshot tables
    my $live = 1;
    setup_temporary_snapshot_views( $db, $timespan );

    # query data
    my $story_links = $db->query( "select * from snapshot_story_links" )->hashes;
    my $story_link_counts = $db->query( "select * from story_link_counts" )->hashes;
    my $snapshot_stories = $db->query( "select * from snapshot_stories" )->hashes;

    discard_temp_tables_and_views( $db );

=head1 DESCRIPTION

Analyze a topic and snapshot the topic to snapshot tables.

For detailed explanation of the snapshot process, see doc/snapshots.markdown.

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use List::MoreUtils qw(natatime);
use List::Util;
use Readonly;

use MediaWords::DBI::Activities;
use MediaWords::DBI::Snapshots;
use MediaWords::Job::Broker;
use MediaWords::Job::State;
use MediaWords::Solr;
use MediaWords::TM::Alert;
use MediaWords::TM::Dump;
use MediaWords::TM::Model;
use MediaWords::TM::Snapshot::Views;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::SQL;

# list of platforms for which we should run url sharing timespans
Readonly my $URL_SHARING_PLATFORMS => [ qw/twitter reddit generic_post/ ];

Readonly my $TECHNIQUE_BOOLEAN => 'Boolean Query';
Readonly my $TECHNIQUE_SHARING => 'URL Sharing';

# only include posts in a topic that have fewer than this propotion of the total shares
Readonly my $AUTHOR_COUNT_MAX_SHARE => 0.01;

# but don't elimiate any authors with fewer than this many shares
Readonly my $AUTHOR_COUNT_MIN_CUTOFF => 100;

# update the job state args, catching any error caused by not running within a job
sub _update_job_state_args($$$)
{
    my ( $db, $state_updater, $args ) = @_;

    unless ( $state_updater ) {
        # Shouldn't happen but let's check nonetheless
        ERROR "State updater is unset.";
        return;
    }

    $state_updater->update_job_state_args( $db, $args );
}

# update the job state message, catching any error caused by not running within a job
sub _update_job_state_message($$$)
{
    my ( $db, $state_updater, $message ) = @_;

    unless ( $state_updater ) {
        # Shouldn't happen but let's check nonetheless
        ERROR "State updater is unset.";
        return;
    }

    $state_updater->update_job_state_message( $db, $message );
}

# given a timespans, return the topic_seed_queries_id associated with the parent focus, if any.
# return if no such focal_set exists.
sub _get_timespan_seed_query($$)
{
    my ( $db, $timespan ) = @_;

    my ( $topic_seed_queries_id ) = $db->query( <<SQL,
        SELECT foci.arguments->>'topic_seed_queries_id'
        FROM foci
            INNER JOIN focal_sets ON
                foci.topics_id = focal_sets.topics_id AND
                foci.focal_sets_id = focal_sets.focal_sets_id
        WHERE
            foci.topics_id = ? AND
            foci.foci_id = ? AND
            focal_sets.focal_technique = ?
SQL
        $timespan->{ topics_id }, $timespan->{ foci_id }, $TECHNIQUE_SHARING
    )->flat;

    return $topic_seed_queries_id ? int( $topic_seed_queries_id ) : undef;
}

# remove stories from snapshot_period_stories that don't match solr query in the associated focus, if any
sub _restrict_period_stories_to_boolean_focus($$)
{
    my ( $db, $timespan ) = @_;

    my $focus = $db->require_by_id( 'foci', $timespan->{ foci_id } );

    my $arguments = MediaWords::Util::ParseJSON::decode_json( $focus->{ arguments } );

    my $solr_q = $arguments->{ query };

    my $snapshot_period_stories_ids = $db->query( "SELECT stories_id FROM snapshot_period_stories" )->flat;

    if ( !@{ $snapshot_period_stories_ids } )
    {
        $db->query( "TRUNCATE TABLE snapshot_period_stories" );
        return;

    }
    my $all_stories_ids      = [ @{ $snapshot_period_stories_ids } ];
    my $matching_stories_ids = [];
    my $chunk_size           = 100000;
    my $min_chunk_size       = 10;
    my $max_solr_errors      = 10;
    my $solr_error_count     = 0;

    my $i = 0;
    while ( @{ $all_stories_ids } )
    {
        my $stories_count = scalar( @{ $all_stories_ids } );
        DEBUG( "remaining stories: $stories_count" );

        my $chunk_stories_ids = [];
        $chunk_size = List::Util::min( $chunk_size, scalar( @{ $all_stories_ids } ) );
        map { push( @{ $chunk_stories_ids }, shift( @{ $all_stories_ids } ) ) } ( 1 .. $chunk_size );

        die( "focus boolean query '$solr_q' must include non-space character" ) unless ( $solr_q =~ /[^[:space:]]/ );

        my $stories_ids_list = join( ' ', @{ $chunk_stories_ids } );
        my $chunk_solr_q = "( $solr_q ) and stories_id:( $stories_ids_list )";

        DEBUG( "solr query: " . substr( $chunk_solr_q, 0, 128 ) );

        my $solr_stories_ids =
          eval { MediaWords::Solr::search_solr_for_stories_ids( $db, { 'rows' => 10000000, 'q' => $chunk_solr_q } ) };
        if ( $@ )
        {
            # sometimes solr throws a NullException error on one of these queries; retrying with smaller
            # chunks seems to make it happy; if the error keeps happening, just drop those stories_ids
            if ( ++$solr_error_count > $max_solr_errors )
            {
                die( "too many solr errors: $@" );
            }

            $chunk_size = List::Util::max( $chunk_size / 2, $min_chunk_size );
            unshift( @{ $all_stories_ids }, @{ $chunk_stories_ids } );

            my $sleep_time = 2 ** $solr_error_count;

            DEBUG( "solr error # $solr_error_count, new chunk size: $chunk_size, sleeping $sleep_time ...\n$@" );
        }
        else
        {
            DEBUG( "solr stories found: " . scalar( @{ $solr_stories_ids } ) );
            push( @{ $matching_stories_ids }, @{ $solr_stories_ids } );
        }
    }

    $matching_stories_ids = [ map { int( $_ ) } @{ $matching_stories_ids } ];

    DEBUG( "restricting timespan to focus query: " . scalar( @{ $matching_stories_ids } ) . " stories" );

    my $ids_table = $db->get_temporary_ids_table( $matching_stories_ids );

    $db->query( <<"SQL"
        DELETE FROM snapshot_period_stories
        WHERE stories_id not IN (
            SELECT id
            FROM $ids_table
        )
SQL
    );
}

# get the where clause that will restrict the snapshot_period_stories creation
# to only stories within the timespan time frame
sub _get_period_stories_date_where_clause
{
    my ( $timespan ) = @_;

    my $date_clause = <<SQL;
        (
            (s.publish_date BETWEEN \$1::timestamp AND \$2::timestamp - INTERVAL '1 second') OR
            (ss.publish_date BETWEEN \$1::timestamp AND \$2::timestamp - INTERVAL '1 second')
        )
SQL

    return $date_clause;
}

# for a url sharing timespan, the only stories that should appear in the timespan are stories associated
# with a post published during the timespan
sub _create_url_sharing_snapshot_period_stories($$)
{
    my ( $db, $timespan ) = @_;

    my $topic_seed_queries_id = _get_timespan_seed_query( $db, $timespan );

    $db->query( <<SQL,
        CREATE TEMPORARY TABLE snapshot_period_stories AS
            SELECT DISTINCT stories_id
            FROM topic_post_stories
            WHERE
                topics_id = ? AND
                topic_seed_queries_id = ? AND
                publish_date >= ? AND
                publish_date < ?
SQL
        $timespan->{ topics_id },
        $topic_seed_queries_id,
        $timespan->{ start_date },
        $timespan->{ end_date },
    );
}

# restrict the set of stories to the current timespan based on publish date or referencing story
# publish date.  a story should be in the current snapshot if either its date is within
# the period dates or if a story that links to it has a date within the period dates.
# For this purpose, stories tagged with the 'date_invalid:undateable' tag
# are considered to have an invalid tag, so their dates cannot be used to pass
# either of the above tests.
sub _create_link_snapshot_period_stories($$)
{
    my ( $db, $timespan ) = @_;

    if ( $timespan->{ period } eq 'overall' )
    {
        $db->query( <<SQL
            CREATE TEMPORARY TABLE snapshot_period_stories AS
                SELECT stories_id
                FROM snapshot_stories
SQL
        );
        return;
    }

    my $date_where_clause = _get_period_stories_date_where_clause( $timespan );

    $db->query( <<"SQL",
        CREATE TEMPORARY TABLE snapshot_period_stories AS
            SELECT DISTINCT s.stories_id
            FROM snapshot_stories AS s
                LEFT JOIN snapshot_topic_links_cross_media AS cl ON
                    cl.ref_stories_id = s.stories_id
                LEFT JOIN snapshot_stories AS ss ON
                    cl.stories_id = ss.stories_id
            WHERE
                (s.publish_date BETWEEN \$1::timestamp AND \$2::timestamp - INTERVAL '1 second') OR
                (ss.publish_date BETWEEN \$1::timestamp AND \$2::timestamp - INTERVAL '1 second')
SQL
        $timespan->{ start_date }, $timespan->{ end_date }
    );

}

# return true if the topic of the timespan is not a web topic
sub _timespan_is_url_sharing
{
    my ( $db, $timespan ) = @_;

    return undef unless $timespan->{ foci_id };

    my ( $technique ) = $db->query( <<SQL,
        SELECT focal_technique
        FROM focal_sets
            INNER JOIN foci ON
                focal_sets.topics_id = foci.topics_id AND
                focal_sets.focal_sets_id = foci.focal_sets_id
            WHERE
                focal_sets.topics_id = ? AND
                foci_id = ?
SQL
        $timespan->{ topics_id }, $timespan->{ foci_id }
    )->flat;

    return $technique eq $TECHNIQUE_SHARING;
}

# write snapshot_period_stories table that holds list of all stories that should be included in the
# current period.  For an overall snapshot, every story should be in the current period.
# the definition of period stories depends on whether the topic is a twitter topic or not.
#
# The resulting snapshot_period_stories should be used by all other snapshot queries to determine
# story membership within a give period.
sub _write_period_stories
{
    my ( $db, $timespan ) = @_;

    $db->query( "drop table if exists snapshot_period_stories" );

    if ( _timespan_is_url_sharing( $db, $timespan ) )
    {
        _create_url_sharing_snapshot_period_stories( $db, $timespan );
    }
    else
    {
        _create_link_snapshot_period_stories( $db, $timespan );

        if ( $timespan->{ foci_id } )
        {
            _restrict_period_stories_to_boolean_focus( $db, $timespan );
        }
    }

    my ( $num_period_stories ) = $db->query( "SELECT COUNT(*) FROM snapshot_period_stories" )->flat;
    DEBUG( "num_period_stories: $num_period_stories" );
}

# convenience function to update a field in the timespan table
sub update_timespan
{
    my ( $db, $timespan, $field, $val ) = @_;

    $db->update_by_id( 'timespans', $timespan->{ timespans_id }, { $field => $val } );
}

sub _create_url_sharing_story_links($$)
{
    my ( $db, $timespan ) = @_;

    my $topic_seed_queries_id = _get_timespan_seed_query( $db, $timespan );

    # get and index a list of post-story-shares with publish dat and author
    $db->query( <<SQL
        CREATE TEMPORARY TABLE _post_stories AS
            SELECT DISTINCT
                s.media_id,
                s.stories_id,
                tp.author,
                tp.publish_date,
                EXTRACT(epoch FROM tp.publish_date) AS epoch
            FROM snapshot_topic_post_stories AS tp
                INNER JOIN snapshot_timespan_posts USING (topic_posts_id)
                INNER JOIN snapshot_stories AS s USING (stories_id)
SQL
    );

    $db->query( <<SQL
        CREATE INDEX _post_stories_auth ON _post_stories (author, epoch)
SQL
    );

    my ( $num_stories ) = $db->query( "SELECT COUNT(DISTINCT stories_id) FROM _post_stories" )->flat();
    my $story_pairs_limit = $num_stories * 2;

    # start trying to get no more than $story_pairs_limit matches using a year long interval.  if the limit is
    # reached, try a smaller interval.  keep trying until the limit is not reached.  this protects us from the query
    # runing into a query bomb that runs forever if there are lots of stories and a small set of shared authors.
    my $interval = 86400 * 365;
    my $found_interval = 0;
    while ( $interval > 0 )
    {
        $db->query( "DROP TABLE IF EXISTS _dated_story_pairs" );

        $db->query( <<SQL,
            CREATE TEMPORARY TABLE _dated_story_pairs AS
                SELECT
                    a.stories_id AS stories_id_a,
                    b.stories_id AS stories_id_b,
                    ABS(a.epoch - b.epoch) AS date_diff
                FROM _post_stories AS a
                    INNER JOIN _post_stories AS b USING (author)
                WHERE
                    a.media_id != b.media_id AND
                    a.stories_id > b.stories_id AND
                    a.epoch BETWEEN b.epoch - \$1 AND b.epoch + \$1
                LIMIT \$2
SQL
            $interval, $story_pairs_limit
        );
            
        my ( $num_dated_story_pairs ) = $db->query( "SELECT COUNT(*) FROM _dated_story_pairs" )->flat();
        if ( $num_dated_story_pairs < $story_pairs_limit )
        {
            INFO( "Found correct interval $interval with $num_dated_story_pairs / $story_pairs_limit pairs" );
            $found_interval = 1;
            last;
        }

        DEBUG( "Trying smaller interval: $interval (found $num_dated_story_pairs / $story_pairs_limit )" );

        $interval = int( $interval / 2 );
        $interval = ( $interval < 14400 ) ? 0 : $interval;
    }

    # if we never found an interval with few enough pairs, just cowardly refuse to create story links,
    # since there is no reasonable way to do so if we have too many pairs even with a 0 interval
    if ( !$found_interval )
    {
        WARN( "Unable to find minimum interval for dated story pairs. Using empty story_links" );
        $db->query( "TRUNCATE TABLE _dated_story_pairs" );
    }

    # query the pairs of cross-media stories with the shortest time between shares by the same author
    $db->query( <<SQL,
        CREATE TEMPORARY TABLE snapshot_story_links AS
            SELECT
                stories_id_a AS source_stories_id,
                stories_id_b AS ref_stories_id,
                MIN(date_diff) AS min_date_diff
            FROM _dated_story_pairs
            GROUP BY
                stories_id_a,
                stories_id_b
            ORDER BY min_date_diff ASC
            LIMIT ?
SQL
        $num_stories
    );

    $db->query( <<SQL );
        DROP TABLE _post_stories
SQL

    $db->query( <<SQL );
        DROP TABLE _dated_story_pairs
SQL
}

sub _write_story_links_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "DROP TABLE IF EXISTS snapshot_story_links" );

    if ( _timespan_is_url_sharing( $db, $timespan ) )
    {
        _create_url_sharing_story_links( $db, $timespan );
    }
    else
    {
        my $query = <<SQL;
            CREATE TEMPORARY TABLE snapshot_story_links AS
                SELECT DISTINCT
                    cl.stories_id AS source_stories_id,
                    cl.ref_stories_id
                FROM snapshot_topic_links_cross_media AS cl
                    INNER JOIN snapshot_period_stories AS sps ON
                        cl.stories_id = sps.stories_id
                    INNER JOIN snapshot_stories AS s ON
                        sps.stories_id = s.stories_id
                    INNER JOIN snapshot_period_stories AS rps ON
                        cl.ref_stories_id = rps.stories_id
                    LEFT JOIN stories_ap_syndicated AS sap ON
                        sps.stories_id = sap.stories_id
                WHERE
                    sap.ap_syndicated IS NULL OR
                    sap.ap_syndicated = false
SQL

        if ( $timespan->{ period } ne 'overall' )
        {
            $db->query( <<"SQL",
                $query AND
                (s.publish_date BETWEEN \$1::timestamp AND \$2::timestamp - INTERVAL '1 second' )
SQL
                $timespan->{ start_date }, $timespan->{ end_date }
            );
        }
        else
        {
            $db->query( $query );
        }
    }

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'story_links' );
    }
}

sub _write_timespan_posts_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "DROP TABLE IF EXISTS snapshot_timespan_posts" ); 

    my $tsq_id = _get_timespan_seed_query( $db, $timespan );

    my $start_date = $timespan->{ start_date };
    my $end_date = $timespan->{ end_date };

    # get all posts that should be included in the timespan. eliminate authors
    # that are too prolific to avoid bots
    $db->query( <<SQL,
        CREATE TEMPORARY TABLE snapshot_timespan_posts AS
            SELECT DISTINCT topic_posts_id
            FROM snapshot_topic_post_stories
            WHERE
                topic_seed_queries_id = ? AND
                publish_date >= ? AND
                publish_date < ?
SQL
        $tsq_id, $start_date, $end_date
    );

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'timespan_posts' );
    }
}

sub _write_story_link_counts_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "DROP TABLE IF EXISTS snapshot_story_link_counts" );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE snapshot_story_link_counts AS

            WITH snapshot_story_media_links AS (
               SELECT
                    s.media_id AS source_media_id,
                    sl.ref_stories_id AS ref_stories_id
                FROM snapshot_story_links AS sl
                    INNER JOIN snapshot_stories AS s ON
                        s.stories_id = sl.source_stories_id
                GROUP BY
                    s.media_id,
                    sl.ref_stories_id
            ),

            snapshot_story_media_link_counts AS (
                SELECT
                    COUNT(*) AS media_inlink_count,
                    ref_stories_id AS stories_id
                FROM snapshot_story_media_links
                GROUP BY ref_stories_id
            ),

            snapshot_post_counts AS (
                select
                    tps.stories_id,
                    COUNT(*) AS post_count,
                    COUNT(DISTINCT tp.author) AS author_count,
                    COUNT(DISTINCT tp.channel) AS channel_count
                FROM snapshot_timespan_posts AS stp
                    INNER JOIN snapshot_topic_post_stories AS tps USING (topic_posts_id)
                    INNER JOIN topic_posts AS tp ON
                        tps.topics_id = topic_posts.topics_id AND
                        tps.topic_posts_id = topic_posts.topic_posts_id
                GROUP BY tps.stories_id
            )

            SELECT DISTINCT
                ps.stories_id,
                COALESCE(smlc.media_inlink_count, 0) AS media_inlink_count,
                COALESCE(ilc.inlink_count, 0) AS inlink_count,
                COALESCE(olc.outlink_count, 0) AS outlink_count,
                stc.post_count,
                stc.author_count,
                stc.channel_count,
                ss.facebook_share_count AS facebook_share_count
            FROM snapshot_period_stories AS ps
                LEFT JOIN snapshot_story_media_link_counts AS smlc USING (stories_id)
                LEFT JOIN (
                    SELECT
                        sl.ref_stories_id,
                        COUNT(DISTINCT sl.source_stories_id) AS inlink_count
                    FROM
                        snapshot_story_links AS sl,
                        snapshot_period_stories AS ps
                    WHERE sl.source_stories_id = ps.stories_id
                    GROUP BY sl.ref_stories_id
                ) AS ilc ON
                    ps.stories_id = ilc.ref_stories_id
                LEFT JOIN (
                    SELECT
                        sl.source_stories_id AS stories_id,
                        COUNT(DISTINCT sl.ref_stories_id) AS outlink_count
                    FROM
                        snapshot_story_links AS sl,
                        snapshot_period_stories AS ps
                    WHERE sl.ref_stories_id = ps.stories_id
                    GROUP BY sl.source_stories_id
                ) AS olc ON
                    ps.stories_id = olc.stories_id
                LEFT JOIN story_statistics AS ss ON
                    ss.stories_id = ps.stories_id
                LEFT JOIN snapshot_post_counts AS stc ON
                    stc.stories_id = ps.stories_id
SQL
    );

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'story_link_counts' );
    }
}

sub _write_medium_link_counts_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "DROP TABLE IF EXISTS snapshot_medium_link_counts" );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE snapshot_medium_link_counts AS

            WITH medium_media_link_counts AS (
               SELECT
                    COUNT(*) AS media_inlink_count,
                    ref_media_id AS media_id
                FROM snapshot_medium_links
                GROUP BY ref_media_id
            ),

            medium_link_counts AS (
                select
                    m.media_id,
                    SUM(slc.media_inlink_count) AS sum_media_inlink_count,
                    SUM(slc.inlink_count) AS inlink_count,
                    SUM(slc.outlink_count) AS outlink_count,
                    COUNT(*) AS story_count,
                    SUM(slc.facebook_share_count) AS facebook_share_count,
                    SUM(slc.post_count) AS sum_post_count,
                    SUM(slc.author_count) AS sum_author_count,
                    SUM(slc.channel_count) AS sum_channel_count
                FROM snapshot_media AS m
                    INNER JOIN snapshot_stories AS s USING (media_id)
                    INNER JOIN snapshot_story_link_counts AS slc USING (stories_id)
                WHERE
                    m.media_id = s.media_id AND
                    s.stories_id = slc.stories_id
                GROUP BY m.media_id
            )

            SELECT
                mlc.*,
                COALESCE(mmlc.media_inlink_count, 0) AS media_inlink_count
            FROM medium_link_counts AS mlc
                LEFT JOIN medium_media_link_counts AS mmlc USING (media_id)
SQL
    );

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'medium_link_counts' );
    }
}

sub _write_medium_links_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "DROP TABLE IF EXISTS snapshot_medium_links" );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE snapshot_medium_links AS
            SELECT
                s.media_id AS source_media_id,
                r.media_id AS ref_media_id,
                COUNT(*) AS link_count
            FROM
                snapshot_story_links AS sl,
                snapshot_stories AS s,
                snapshot_stories AS r
            WHERE
                sl.source_stories_id = s.stories_id AND
                sl.ref_stories_id = r.stories_id
            GROUP BY
                s.media_id,
                r.media_id
SQL
    );

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'medium_links' );
    }
}

sub _create_timespan($$$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period, $focus ) = @_;

    my $topics_id = $cd->{ topics_id };
    my $snapshots_id = $cd->{ snapshots_id };
    my $foci_id = $focus ? $focus->{ foci_id } : undef;

    my $focus_clause = $foci_id ? "foci_id = $foci_id" : "foci_id is null";

    my $timespan = $db->query( <<SQL,
        SELECT *
        FROM timespans
        WHERE
            topics_id = \$1 AND
            snapshots_id = \$2 AND
            start_date = \$3 AND
            end_date = \$4 AND
            period = \$5 AND
            $focus_clause
SQL
        $topics_id, $snapshots_id, $start_date, $end_date, $period, $foci_id
    )->hash();

    $timespan ||= $db->query( <<SQL,
        INSERT INTO timespans (
            topics_id,
            snapshots_id,
            start_date,
            end_date,
            period,
            foci_id, 
            story_count,
            story_link_count,
            medium_count,
            medium_link_count,
            post_count
        ) VALUES (
            \$1,
            \$2,
            \$3,
            \$4,
            \$5,
            \$6,
            0,
            0,
            0,
            0,
            0
        )
        RETURNING *
SQL
        $topics_id, $snapshots_id, $start_date, $end_date, $period, $foci_id
    )->hash();

    $timespan->{ snapshot } = $cd;

    return $timespan;
}

# return true if there exists at least one row in the relevant table for which timespans_id = $timespans_id
sub _timespan_snapshot_exists($$$)
{
    my ( $db, $table, $timespan ) = @_;

    die( "Table name can only have letters and underscores" ) if ( $table =~ /[^a-z_]/i );

    my $exists = $db->query( <<SQL,
        SELECT 1
        FROM snap.$table
        WHERE
            topics_id = ? AND
            timespans_id = ?
SQL
        $timespan->{ topics_id }, $timespan->{ timespans_id }
    )->hash();

    return $exists;
}

# generate data for the story_links, story_link_counts, media_links, media_link_counts tables
# based on the data in the temporary snapshot_* tables
sub generate_timespan_data($$;$)
{
    my ( $db, $timespan, $is_model ) = @_;

    if ( _timespan_snapshot_exists( $db, 'medium_link_counts', $timespan ) )
    {
        DEBUG( "timespan already exists.  skipping ..." );
        return;
    }

    my $all_models_top_media = MediaWords::TM::Model::get_all_models_top_media( $db, $timespan );

    _write_period_stories( $db, $timespan );

    _write_timespan_posts_snapshot( $db, $timespan );

    _write_story_links_snapshot( $db, $timespan, $is_model );
    _write_story_link_counts_snapshot( $db, $timespan, $is_model );
    _write_medium_links_snapshot( $db, $timespan, $is_model );
    _write_medium_link_counts_snapshot( $db, $timespan, $is_model );

    _update_timespan_counts( $db, $timespan );
    _write_medium_links_snapshot( $db, $timespan, $is_model );
    _write_medium_link_counts_snapshot( $db, $timespan, $is_model );

    _update_timespan_counts( $db, $timespan );

    $all_models_top_media ||= [ MediaWords::TM::Model::get_top_media_link_counts( $db, $timespan ) ];

    MediaWords::TM::Model::print_model_matches( $db, $timespan, $all_models_top_media );
    MediaWords::TM::Model::update_model_correlation( $db, $timespan, $all_models_top_media );

    INFO "Adding a new topics-map job for timespan";
    my $timespans_id = $timespan->{ timespans_id };

    MediaWords::Job::Broker->new( 'MediaWords::Job::TM::Map' )->add_to_queue( { timespans_id => $timespans_id } );

    MediaWords::TM::Dump::dump_timespan( $db, $timespan );
}

# Update story_count, story_link_count, medium_count, and medium_link_count
# fields in the timespan hash. This must be called after
# setup_temporary_snapshot_views() to get access to these fields in the
# timespan hash.
#
# Save to db unless $live is specified.
sub _update_timespan_counts($$;$)
{
    my ( $db, $timespan, $live ) = @_;

    ( $timespan->{ story_count } ) = $db->query( "SELECT COUNT(*) FROM snapshot_story_link_counts" )->flat;

    ( $timespan->{ story_link_count } ) = $db->query( "SELECT COUNT(*) FROM snapshot_story_links" )->flat;

    ( $timespan->{ medium_count } ) = $db->query( "SELECT COUNT(*) FROM snapshot_medium_link_counts" )->flat;

    ( $timespan->{ medium_link_count } ) = $db->query( "SELECT COUNT(*) FROM snapshot_medium_links" )->flat;

    ( $timespan->{ post_count } ) = $db->query( "SELECT COUNT(*) FROM snapshot_timespan_posts" )->flat;

    return if ( $live );

    for my $field ( qw(story_count story_link_count medium_count medium_link_count) )
    {
        update_timespan( $db, $timespan, $field, $timespan->{ $field } );
    }
}

# generate the snapshot timespans for the given period, dates, and tag
sub _generate_timespan($$$$$$;$)
{
    my ( $db, $snapshot, $start_date, $end_date, $period, $focus, $state_updater ) = @_;

    my $timespan = _create_timespan( $db, $snapshot, $start_date, $end_date, $period, $focus );

    my $snapshot_label = "${ period }: ${ start_date } - ${ end_date } ";
    $snapshot_label .= "[ $focus->{ name } ]" if ( $focus );

    DEBUG( "generating $snapshot_label ..." );

    _update_job_state_message( $db, $state_updater, "snapshotting $snapshot_label" );

    DEBUG( "generating snapshot data ..." );
    generate_timespan_data( $db, $timespan );
}

# decrease the given date to the latest monday equal to or before the date
sub _truncate_to_monday($)
{
    my ( $date ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $week_day   = ( localtime( $epoch_date ) )[ 6 ];

    # mod this to account for sunday, for which $week_day - 1 == -1
    my $days_offset = ( $week_day - 1 ) % 7;

    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# decrease the given date to the first day of the current month
sub _truncate_to_start_of_month ($)
{
    my ( $date ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $month_day  = ( localtime( $epoch_date ) )[ 3 ];

    my $days_offset = $month_day - 1;

    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# generate snapshots for the periods in topic_dates
sub _generate_custom_period_snapshot($$$;$)
{
    my ( $db, $cd, $focus, $state_updater ) = @_;

    my $topic_dates = $db->query( <<SQL,
        SELECT *
        FROM topic_dates
        WHERE topics_id = ?
        ORDER BY
            start_date,
            end_date
SQL
        $cd->{ topics_id }
    )->hashes;

    for my $topic_date ( @{ $topic_dates } )
    {
        my $start_date = $topic_date->{ start_date };
        my $end_date   = $topic_date->{ end_date };
        _generate_timespan( $db, $cd, $start_date, $end_date, 'custom', $focus, $state_updater );
    }
}

# generate snapshot for the given period (overall, monthly, weekly, or custom) and the given tag
sub _generate_period_snapshot($$$$;$)
{
    my ( $db, $cd, $period, $focus, $state_updater ) = @_;

    my $start_date = $cd->{ start_date };
    my $end_date   = $cd->{ end_date };

    if ( $period eq 'overall' )
    {
        # this will generate an 'overall' timespan with all stories
        _generate_timespan( $db, $cd, $start_date, $end_date, $period, $focus );
    }
    elsif ( $period eq 'weekly' )
    {
        my $w_start_date = _truncate_to_monday( $start_date );
        while ( $w_start_date lt $end_date )
        {
            my $w_end_date = MediaWords::Util::SQL::increment_day( $w_start_date, 7 );

            _generate_timespan( $db, $cd, $w_start_date, $w_end_date, $period, $focus );

            $w_start_date = $w_end_date;
        }
    }
    elsif ( $period eq 'monthly' )
    {
        my $m_start_date = _truncate_to_start_of_month( $start_date );
        while ( $m_start_date lt $end_date )
        {
            my $m_end_date = MediaWords::Util::SQL::increment_day( $m_start_date, 32 );
            $m_end_date = _truncate_to_start_of_month( $m_end_date );

            _generate_timespan( $db, $cd, $m_start_date, $m_end_date, $period, $focus );

            $m_start_date = $m_end_date;
        }
    }
    elsif ( $period eq 'custom' )
    {
        _generate_custom_period_snapshot( $db, $cd, $focus, $state_updater );
    }
    else
    {
        die( "Unknown period '$period'" );
    }
}

# create a snapshot for the given table from the temporary snapshot_* table,
# making sure to specify all the fields in the copy so that we don't have to
# assume column position is the same in the original and snapshot tables.
# use the $key from $obj as an additional field in the snapshot table.
sub _create_snapshot
{
    my ( $db, $obj, $key, $table ) = @_;

    DEBUG( "snapshot $table..." );

    die( "Table name can only have letters and underscores" ) if ( $table =~ /[^a-z_]/i );
    die( "Key can only have letters and underscores" )        if ( $key =~ /[^a-z_]/i );

    my $snapshot_exists = $db->query( "SELECT 1 FROM snap.$table WHERE $key = $obj->{ $key }" )->hash();
    if ( $snapshot_exists )
    {
        DEBUG( "snapshot $table already exists.  skipping ..." );
        return;
    }

    my $column_names = [ $db->query( <<SQL,
        SELECT column_name
        FROM information_schema.columns
        WHERE
            table_name = ? AND
            table_schema = 'snap' AND
            column_name NOT IN (?)
        ORDER BY ordinal_position ASC
SQL
        $table, $key
    )->flat ];

    die( "Field names can only have letters and underscores" ) if ( grep { /[^a-z_]/i } @{ $column_names } );

    my $column_list = join( ",", @{ $column_names } );

    $db->query( <<"SQL",
        INSERT INTO snap.${ table } ($column_list, $key)
            SELECT $column_list, ?
            FROM snapshot_${ table }
SQL
        $obj->{ $key }
    );

}

# create a snapshot of a table for a timespan
sub _create_timespan_snapshot
{
    my ( $db, $timespan, $table ) = @_;

    _create_snapshot( $db, $timespan, 'timespans_id', $table );
}

# create a snapshot of a table for a snapshot
sub create_snap_snapshot
{
    my ( $db, $cd, $table ) = @_;

    _create_snapshot( $db, $cd, 'snapshots_id', $table );
}

# add only the stories that aren't already in snapshot_stories_tags_map
sub _create_snapshot_stories_tags_map($$)
{
    my ( $db, $snapshot ) = @_;

    $db->query( <<SQL
        CREATE TEMPORARY TABLE snapshot_stories_tags_map AS
            SELECT *
            FROM stories_tags_map
            LIMIT 0
SQL
    );

    $db->query( <<SQL, 
        INSERT INTO snapshot_stories_tags_map (
            stories_id,
            tags_id
        )
            SELECT
                stories_id,
                tags_id
            FROM snap.stories_tags_map
            WHERE
                topics_id = ? AND
                snapshots_id = ?
SQL
        $snapshot->{ topics_id }, $snapshot->{ snapshots_id }
    );
    
    my $new_stories_ids = $db->query( <<SQL
        SELECT stories_id
        FROM snapshot_stories
        WHERE stories_id NOT IN (
            SELECT stories_id
            FROM snapshot_stories_tags_map
        )
SQL
    )->flat;

    for my $new_stories_id ( @{ $new_stories_ids } )
    {
        my $tags_ids = $db->query( <<SQL,
            SELECT tags_id
            FROM stories_tags_map
            WHERE stories_id = ?
SQL
            $new_stories_id
        )->flat;
        return unless @{ $tags_ids };

        my $values_list = join( ',', map { "($new_stories_id, $_)" } @{ $tags_ids } );

        $db->query( <<"SQL"
            INSERT INTO snapshot_stories_tags_map (stories_id, tags_id)
            VALUES $values_list
SQL
        );
    }   
}

# create snapshot_topic_stories, which defines a superset of the stories to be included in the topic.
# if the topic.only_snapshot_engaged_stories is true, prune stories to only those that
# have a minium number of inlinks, fb shares, or twitter shares
sub _create_snapshot_topic_stories($$)
{
    my ( $db, $topic ) = @_;

    if ( !$topic->{ only_snapshot_engaged_stories } )
    {
        $db->query( <<SQL,
            CREATE TEMPORARY TABLE snapshot_topic_stories AS
                SELECT *
                FROM topic_stories
                WHERE topics_id = ?
SQL
            $topic->{ topics_id }
        );
    }
    else
    {
        $db->query( <<SQL,
            CREATE TEMPORARY TABLE snapshot_topic_stories AS 

                WITH link_stories AS (
                    SELECT ts.stories_id
                    FROM topic_links AS tl
                        INNER JOIN topic_stories AS ts ON
                            ts.stories_id = tl.ref_stories_id AND
                            ts.topics_id = tl.topics_id
                    WHERE tl.topics_id = \$1
                ),

                post_stories AS (
                    SELECT stories_id
                    FROM topic_post_stories
                    WHERE topics_id = \$1
                    GROUP BY
                        topic_seed_queries_id,
                        stories_id
                    HAVING COUNT(*) >= 10
                )

                SELECT *
                FROM topic_stories
                WHERE
                    topics_id = \$1 AND
                    stories_id IN (
                        SELECT stories_id
                        FROM link_stories

                        UNION

                        SELECT stories_id
                        FROM post_stories
                    )
SQL
            $topic->{ topics_id }
        );
    }
}

# generate temporary snapshot_* tables for the specified snapshot for each of the snapshot_tables.
# these are the tables that apply to the whole snapshot.
sub _write_temporary_snapshot_tables($$$)
{
    my ( $db, $topic, $snapshot ) = @_;

    my $topics_id = $topic->{ topics_id };

    _create_snapshot_topic_stories( $db, $topic );

    $db->query( <<SQL,
        CREATE TEMPORARY TABLE snapshot_topic_media_codes AS
            SELECT *
            FROM topic_media_codes
            WHERE topics_id = ?
SQL
        $topics_id
    );

    DEBUG( "creating snapshot_stories ..." );
    $db->query( <<SQL,
        CREATE TEMPORARY TABLE snapshot_stories AS
            SELECT
                s.stories_id,
                s.media_id,
                s.url,
                s.guid,
                s.title,
                s.publish_date,
                s.collect_date,
                s.full_text_rss,
                s.language
            FROM snap.live_stories AS s
                JOIN snapshot_topic_stories AS dcs ON
                    s.topics_id = dcs.topics_id AND
                    s.stories_id = dcs.stories_id
            WHERE s.topics_id = ?
SQL
        $topics_id
    );

    DEBUG( "creating snapshot_media ..." );
    $db->query( <<SQL
        CREATE TEMPORARY TABLE snapshot_media AS
            SELECT *
            FROM media
            WHERE media_id IN (
                SELECT media_id
                FROM snapshot_stories
            )
SQL
    );

    DEBUG( "creating snapshot_topic_links_cross_media" );
    $db->query( <<SQL,
        CREATE TEMPORARY TABLE snapshot_topic_links_cross_media AS
            SELECT
                s.stories_id,
                r.stories_id AS ref_stories_id,
                cl.url,
                cs.topics_id,
                cl.topic_links_id
            FROM topic_links AS cl
                INNER JOIN snapshot_topic_stories AS cs ON
                    cs.topics_id = cl.topics_id AND
                    cs.stories_id = cl.ref_stories_id
                INNER JOIN snapshot_stories AS s ON
                    cl.stories_id = s.stories_id
                INNER JOIN snapshot_media AS sm ON
                    s.media_id = sm.media_id
                INNER JOIN snapshot_stories AS r ON
                    cl.ref_stories_id = r.stories_id
                INNER JOIN snapshot_media AS rm ON
                    r.media_id = rm.media_id
            WHERE
                cl.topics_id = ? AND
                r.media_id != s.media_id
SQL
        $topics_id
    );


    DEBUG( "creating snapshot_stories_tags_map ..." );
    _create_snapshot_stories_tags_map( $db, $snapshot );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE snapshot_media_tags_map AS
            SELECT mtm.*
            FROM
                media_tags_map AS mtm,
                snapshot_media AS dm
            WHERE mtm.media_id = dm.media_id
SQL
    );

    DEBUG( "creating snapshot_topic_post_stories ..." );
    $db->query( <<SQL,
        CREATE TEMPORARY TABLE snapshot_topic_post_stories AS
            WITH _all_topic_post_stories AS (
                SELECT
                    COUNT(*) OVER (PARTITION BY author, topic_seed_queries_id) AS author_count,
                    COUNT(*) OVER (PARTITION BY topic_seed_queries_id) AS query_count,
                    *
                FROM topic_post_stories
            )
            
            SELECT *
            FROM _all_topic_post_stories
            WHERE author_count < GREATEST(?, query_count * ?)
SQL
        $AUTHOR_COUNT_MIN_CUTOFF, $AUTHOR_COUNT_MAX_SHARE
    );

    my $tweet_topics_id = $topic->{ topics_id };

    MediaWords::TM::Snapshot::Views::add_media_type_views( $db );

    for my $table ( @{ MediaWords::TM::Snapshot::Views::get_snapshot_tables() } )
    {
        my $table_exists = $db->query( "SELECT * FROM pg_class WHERE relname = 'snapshot_' || ?", $table )->hash;
        die( "snapshot not created for snapshot table: $table" ) unless ( $table_exists );
    }

}

# generate snapshots for all of the get_snapshot_tables() from the temporary snapshot tables
sub _generate_snapshots_from_temporary_snapshot_tables
{
    my ( $db, $cd ) = @_;

    my $snapshot_tables = MediaWords::TM::Snapshot::Views::get_snapshot_tables();

    map { create_snap_snapshot( $db, $cd, $_ ) } @{ $snapshot_tables };
}

# create focal_set and focus definitons for the url sharing platforms present in seed queries for the topic
sub _update_url_sharing_focus_definitions($$)
{
    my ( $db, $snapshot ) = @_;

    my $tsqs = $db->query( "select * from topic_seed_queries where topics_id = ?", $snapshot->{ topics_id } )->hashes;

    if ( !@{ $tsqs } )
    {
        $db->query( <<SQL,
            DELETE FROM focal_set_definitions
            WHERE
                focal_technique = ? AND
                topics_id = ?
SQL
            $TECHNIQUE_SHARING, $snapshot->{ topics_id }
        );
        return;
    }

    my $fsd = {
        topics_id => $snapshot->{ topics_id },
        name => $TECHNIQUE_SHARING,
        description => 'Subtopics for analysis of url cosharing on urls collected by platform seed queries.',
        focal_technique =>  'URL Sharing'
    };
    $fsd = $db->find_or_create( 'focal_set_definitions', $fsd );

    for my $tsq ( @{ $tsqs } )
    {
        next unless ( grep { $tsq->{ platform } eq $_ } @{ $URL_SHARING_PLATFORMS } );

        my $fsd_id = $fsd->{ focal_set_definitions_id };
        my $topic_seed_queries_id = $tsq->{ topic_seed_queries_id };

        my $existing_fd = $db->query( <<SQL,
            SELECT *
            FROM focus_definitions
            WHERE
                topics_id = ? AND
                focal_set_definitions_id = ? AND
                (arguments->>'topic_seed_queries_id')::BIGINT = ?::BIGINT
SQL
            $fsd->{ topics_id }, $fsd_id, $topic_seed_queries_id
        )->hash;

        if ( !$existing_fd )
        {
            my $arguments = { mode => 'url_sharing', topic_seed_queries_id => $topic_seed_queries_id };

            my $fd = {
                topics_id => $fsd->{ topics_id },
                focal_set_definitions_id => $fsd->{ focal_set_definitions_id },
                name => "$tsq->{ platform } [$tsq->{ topic_seed_queries_id }]",
                description => "Subtopic for analysis of url cosharing on urls collected from $tsq->{ platform }",
                arguments => MediaWords::Util::ParseJSON::encode_json( $arguments )
            };
            $fd = $db->create( 'focus_definitions', $fd );
        }
    }

    $db->query( <<SQL,
        DELETE FROM focus_definitions AS fd 
        WHERE
            topics_id = \$1 AND
            focal_set_definitions_id = \$2 AND
            NOT EXISTS (
                SELECT 1
                FROM topic_seed_queries AS tsq
                WHERE
                    tsq.topics_id = \$1 AND
                    tsq.topic_seed_queries_id::TEXT = fd.arguments->>'topic_seed_queries_id'
            )
SQL
        $fsd->{ topics_id }, $fsd->{ focal_set_definitions_id }
    );
}

# generate foci from focus definitions, includling updating focus_definitions to include url sharing foci
sub _generate_period_foci($$)
{
    my ( $db, $snapshot ) = @_;

    _update_url_sharing_focus_definitions( $db, $snapshot );

    my $fsds = $db->query( <<SQL,
        SELECT *
        FROM focal_set_definitions
        WHERE topics_id = ?
SQL
        $snapshot->{ topics_id }
    )->hashes;

    my $foci = [];

    for my $fsd ( @{ $fsds } )
    {
        my $focal_set = $db->query( <<SQL,
            INSERT INTO focal_sets (
                name,
                description,
                focal_technique,
                topics_id,
                snapshots_id
            )
                SELECT
                    name,
                    description,
                    focal_technique,
                    \$2 AS topics_id,
                    \$3 AS snapshots_id
                FROM focal_set_definitions
                WHERE
                    focal_set_definitions_id = \$1 AND
                    topics_id = \$2

            ON CONFLICT (topics_id, snapshots_id, name) DO
                UPDATE SET snapshots_id = \$3
            RETURNING *
SQL
            $fsd->{ focal_set_definitions_id }, $snapshot->{ topics_id }, $snapshot->{ snapshots_id }
        )->hash;

        my $fds = $db->query( <<SQL,
            SELECT *
            FROM focus_definitions
            WHERE
                topics_id = ? AND
                focal_set_definitions_id = ?
SQL
            $fsd->{ topics_id }, $fsd->{ focal_set_definitions_id }
        )->hashes;

        for my $fd ( @{ $fds } )
        {
            my $focus = $db->query( <<SQL,
                INSERT INTO foci (
                    name,
                    description,
                    arguments,
                    topics_id,
                    focal_sets_id
                )
                    SELECT
                        name,
                        description,
                        arguments,
                        \$1,
                        \$3
                    FROM focus_definitions
                    WHERE
                        topics_id = \$1 AND
                        focus_definitions_id = \$2

                ON CONFLICT (topics_id, focal_sets_id, name) DO
                    UPDATE SET focal_sets_id = \$3
                RETURNING *
SQL
                $fd->{ topics_id }, $fd->{ focus_definitions_id }, $focal_set->{ focal_sets_id }
            )->hash;

            push( @{ $foci }, $focus );
        }
    }

    return $foci;
}

# generate period spanshots for each period / focus / timespan combination
sub _generate_period_focus_snapshots($$$;$)
{
    my ( $db, $snapshot, $periods, $state_updater ) = @_;

    my $foci = _generate_period_foci( $db, $snapshot );

    for my $focus ( @{ $foci } )
    {
        map { _generate_period_snapshot( $db, $snapshot, $_, $focus, $state_updater ) } @{ $periods };
    }
}

# put all stories in this dump in solr_extra_import_stories for export to solr
sub _export_stories_to_solr($$)
{
    my ( $db, $cd ) = @_;

    DEBUG( "queueing stories for solr import ..." );

    $db->query( <<SQL,
        INSERT INTO solr_import_stories (stories_id)
            SELECT DISTINCT stories_id
            FROM snap.stories
            WHERE
                topics_id = ? AND
                snapshots_id = ?
SQL
        $cd->{ topics_id }, $cd->{ snapshots_id }
    );

    $db->query(<<SQL,
        UPDATE snapshots SET
            searchable = 'f'
        WHERE
            topics_id = ? AND
            snapshots_id = ?
SQL
        $cd->{ topics_id }, $cd->{ snapshots_id }
    );
}

# return list of periods to snapshot, using either topic.snapshot_periods or the default list of all periods
sub _get_snapshot_periods($)
{
    my ( $topic ) = @_;

    if ( my $snapshot_periods = $topic->{ snapshot_periods } )
    {
       my $periods = [ split( ' ', lc( $snapshot_periods ) ) ];
       DEBUG( "limit periods to: " . join( ' ', @{ $periods } ) );

       return $periods;
    }

    return [ qw(custom overall weekly monthly) ];
}

# Create a snapshot for the given topic.  
#
# If a snapshots_id is provided, use the existing snapshot.  Otherwise, create a new one.
#
# Returns snapshots_id of the provided or newly created snapshot.
sub snapshot_topic($$;$$$)
{
    my ( $db, $topics_id, $snapshots_id, $note, $state_updater ) = @_;

    my $topic = $db->require_by_id( 'topics', $topics_id );

    my $periods = _get_snapshot_periods( $topic );

    if ( $topic->{ mode } eq 'url_sharing' )
    {
        die( "url_sharing topics are no longer supported." );
    }

    $db->set_print_warn( 0 );    # avoid noisy, extraneous postgres notices from drops

    # Log activity that's about to start
    my $changes = {};
    unless ( MediaWords::DBI::Activities::log_system_activity( $db, 'tm_snapshot_topic', $topics_id + 0, $changes ) )
    {
        die "Unable to log the 'tm_snapshot_topic' activity.";
    }

    my ( $start_date, $end_date ) = ( $topic->{ start_date }, $topic->{ end_date } );

    my $snap =
        $snapshots_id
      ? $db->require_by_id( 'snapshots', $snapshots_id )
      : MediaWords::DBI::Snapshots::create_snapshot_row( $db, $topic, $start_date, $end_date, $note );

    _update_job_state_args( $db, $state_updater, { snapshots_id => $snap->{ snapshots_id } } );
    _update_job_state_message( $db, $state_updater, "snapshotting data" );

    _write_temporary_snapshot_tables( $db, $topic, $snap );

    _generate_snapshots_from_temporary_snapshot_tables( $db, $snap );

    # generate null focus timespan snapshots
    map { _generate_period_snapshot( $db, $snap, $_, undef ) } ( @{ $periods } );

    _generate_period_focus_snapshots( $db, $snap, $periods, $state_updater );

    MediaWords::TM::Dump::dump_snapshot( $db, $snap );

    _update_job_state_message( $db, $state_updater, "finalizing snapshot" );

    _export_stories_to_solr( $db, $snap );

    MediaWords::TM::Snapshot::Views::discard_temp_tables_and_views( $db );

    # update this manually because snapshot_topic might be called directly from mine_topic()
    $db->update_by_id( 'snapshots', $snap->{ snapshots_id }, { state => $MediaWords::Job::State::STATE_COMPLETED } );
    MediaWords::TM::Alert::send_topic_alert( $db, $topic, "new topic snapshot is ready" );

    return $snap->{ snapshots_id };
}

1;
