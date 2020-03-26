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
use MediaWords::JobManager::AbstractStatefulJob;
use MediaWords::JobManager::Job;
use MediaWords::Solr;
use MediaWords::TM::Alert;
use MediaWords::TM::Model;
use MediaWords::TM::Snapshot::Views;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::SQL;

# possible values of snapshots.bot_policy
Readonly our $POLICY_NO_BOTS   => 'no bots';
Readonly our $POLICY_ONLY_BOTS => 'only bots';
Readonly our $POLICY_BOTS_ALL  => 'all';

# number of tweets per day to use as a threshold for bot filtering
Readonly my $BOT_TWEETS_PER_DAY => 200;

# list of platforms for which we should run url sharing timespans
Readonly my $URL_SHARING_PLATFORMS => [ qw/twitter reddit generic_post/ ];

Readonly my $TECHNIQUE_BOOLEAN => 'Boolean Query';
Readonly my $TECHNIQUE_SHARING => 'URL Sharing';

# update the job state args, catching any error caused by not running within a job
sub _update_job_state_args($$)
{
    my ( $db, $args ) = @_;

    MediaWords::JobManager::AbstractStatefulJob::update_job_state_args( $db, 'MediaWords::Job::TM::SnapshotTopic', $args );
}

# update the job state message, catching any error caused by not running within a job
sub _update_job_state_message($$)
{
    my ( $db, $message ) = @_;

    MediaWords::JobManager::AbstractStatefulJob::update_job_state_message(
        $db,
        'MediaWords::Job::TM::SnapshotTopic',
        $message,
    );
}

# given a timespans, return the topic_seed_queries_id associated with the parent focus, if any.
# return if no such focal_set exists.
sub _get_timespan_seed_query($$)
{
    my ( $db, $timespan ) = @_;

    my ( $topic_seed_queries_id ) = $db->query( <<SQL, $timespan->{ foci_id }, $TECHNIQUE_SHARING )->flat;
select f.arguments->>'topic_seed_queries_id'
    from foci f
        join focal_sets fs using ( focal_sets_id )
    where
        f.foci_id = ? and
        fs.focal_technique = ?
SQL

    return $topic_seed_queries_id ? int( $topic_seed_queries_id ) : undef;
}

# remove stories from snapshot_period_stories that don't match solr query in the associated focus, if any
sub _restrict_period_stories_to_boolean_focus($$)
{
    my ( $db, $timespan ) = @_;

    my $focus = $db->require_by_id( 'foci', $timespan->{ foci_id } );

    my $arguments = MediaWords::Util::ParseJSON::decode_json( $focus->{ arguments } );

    my $solr_q = $arguments->{ query };

    my $snapshot_period_stories_ids = $db->query( "select stories_id from snapshot_period_stories" )->flat;

    if ( !@{ $snapshot_period_stories_ids } )
    {
        $db->query( "truncate table snapshot_period_stories" );
        return;

    }
    my $all_stories_ids      = [ @{ $snapshot_period_stories_ids } ];
    my $matching_stories_ids = [];
    my $chunk_size           = 100000;
    my $min_chunk_size       = 10;
    my $max_solr_errors      = 25;
    my $solr_error_count     = 0;

    while ( @{ $all_stories_ids } )
    {
        my $chunk_stories_ids = [];
        my $chunk_size = List::Util::min( $chunk_size, scalar( @{ $all_stories_ids } ) );
        map { push( @{ $chunk_stories_ids }, shift( @{ $all_stories_ids } ) ) } ( 1 .. $chunk_size );

        die( "focus boolean query '$solr_q' must include non-space character" ) unless ( $solr_q =~ /[^[:space:]]/ );

        my $stories_ids_list = join( ' ', @{ $chunk_stories_ids } );
        $solr_q = "( $solr_q ) and stories_id:( $stories_ids_list )";

        my $solr_stories_ids =
          eval { MediaWords::Solr::search_for_stories_ids( $db, { rows => 10000000, q => $solr_q } ) };
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
            sleep( int( 2**( 1 * ( $solr_error_count / 5 ) ) ) );
        }
        else
        {
            push( @{ $matching_stories_ids }, @{ $solr_stories_ids } );
        }
    }

    $matching_stories_ids = [ map { int( $_ ) } @{ $matching_stories_ids } ];

    DEBUG( "restricting timespan to focus query: " . scalar( @{ $matching_stories_ids } ) . " stories" );

    my $ids_table = $db->get_temporary_ids_table( $matching_stories_ids );

    $db->query( "delete from snapshot_period_stories where stories_id not in ( select id from $ids_table )" );
}

# get the where clause that will restrict the snapshot_period_stories creation
# to only stories within the timespan time frame
sub _get_period_stories_date_where_clause
{
    my ( $timespan ) = @_;

    my $date_clause = <<END;
( ( s.publish_date between \$1::timestamp and \$2::timestamp - interval '1 second'
      and s.stories_id not in ( select stories_id from snapshot_undateable_stories ) ) or
  ( ss.publish_date between \$1::timestamp and \$2::timestamp - interval '1 second'
      and ss.stories_id not in ( select stories_id from snapshot_undateable_stories ) )
)
END

    return $date_clause;
}

# for a url sharing timespan, the only stories that should appear in the timespan are stories associated
# with a post published during the timespan
sub _create_url_sharing_snapshot_period_stories($$)
{
    my ( $db, $timespan ) = @_;

    my $topic_seed_queries_id = _get_timespan_seed_query( $db, $timespan );

    $db->query( <<SQL, $topic_seed_queries_id, $timespan->{ start_date }, $timespan->{ end_date } );
create temporary table snapshot_period_stories as
    select distinct stories_id
        from topic_post_stories
        where
            topic_seed_queries_id = ? and
            publish_date >= ? and publish_date < ?
SQL
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
        $db->query( "create temporary table snapshot_period_stories as select stories_id from snapshot_stories" );
        return;
    }

    $db->query( <<END );
create or replace temporary view snapshot_undateable_stories as
select distinct s.stories_id
    from snapshot_stories s, snapshot_stories_tags_map stm, tags t, tag_sets ts
    where s.stories_id = stm.stories_id and
        stm.tags_id = t.tags_id and
        t.tag_sets_id = ts.tag_sets_id and
        ts.name = 'date_invalid' and
        t.tag = 'undateable'
END

    my $date_where_clause = _get_period_stories_date_where_clause( $timespan );

    $db->query( <<"END", $timespan->{ start_date }, $timespan->{ end_date } );
create temporary table snapshot_period_stories as
select distinct s.stories_id
    from snapshot_stories s
        left join snapshot_topic_links_cross_media cl on ( cl.ref_stories_id = s.stories_id )
        left join snapshot_stories ss on ( cl.stories_id = ss.stories_id )
    where
        $date_where_clause
END

    $db->query( "drop view snapshot_undateable_stories" );
}

# return true if the topic of the timespan is not a web topic
sub _timespan_is_url_sharing
{
    my ( $db, $timespan ) = @_;

    return undef unless $timespan->{ foci_id };

    my ( $technique ) = $db->query( <<SQL, $timespan->{ foci_id } )->flat;
select focal_technique from focal_sets fs join foci using ( focal_sets_id ) where foci_id = ?
SQL

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

    my ( $num_period_stories ) = $db->query( "select count(*) from snapshot_period_stories" )->flat;
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
    $db->query( <<SQL );
create temporary table _post_stories as
    select s.media_id, s.stories_id, tps.author, tps.publish_date, extract( epoch from tps.publish_date ) epoch
        from topic_post_stories tps
            join snapshot_timespan_posts using ( topic_posts_id )
            join stories s using ( stories_id );

create index _post_stories_auth on _post_stories ( author, epoch );
SQL

    my ( $num_stories ) = $db->query( "select count( distinct stories_id ) from _post_stories" )->flat();
    my $story_pairs_limit = $num_stories * 2;

    # start trying to get no more than $story_pairs_limit matches using a year long interval.  if the limit is
    # reached, try a smaller interval.  keep trying until the limit is not reached.  this protects us from the query
    # runing into a query bomb that runs forever if there are lots of stories and a small set of shared authors.
    my $interval = 86400 * 365;
    my $found_interval = 0;
    while ( $interval > 0 )
    {
        $db->query( "drop table if exists _dated_story_pairs" );
        $db->query( <<SQL, $interval, $story_pairs_limit );
create temporary table _dated_story_pairs as 
    select
            a.stories_id stories_id_a,
            b.stories_id stories_id_b,
            abs( a.epoch - b.epoch ) date_diff
        from
            _post_stories a
            join _post_stories b using ( author )
        where
            a.media_id <> b.media_id and
            a.stories_id > b.stories_id and
            a.epoch between b.epoch - \$1 and b.epoch + \$1
        limit \$2
SQL
            
        my ( $num_dated_story_pairs ) = $db->query( "select count(*) from _dated_story_pairs" )->flat();
        if ( $num_dated_story_pairs < $story_pairs_limit )
        {
            INFO( "Found correct interval $interval with $num_dated_story_pairs / $story_pairs_limit pairs" );
            $found_interval = 1;
            last;
        }

        INFO( "Trying smaller interval for_dated_story_pairs: $interval" );

        $interval = int( $interval / 2 );
        $interval = ( $interval < 43200 ) ? 0 : $interval;
    }

    # if we never found an interval with few enough pairs, just cowardly refuse to create story links,
    # since there is no reasonable way to do so if we have too many pairs even with a 0 interval
    if ( !$found_interval )
    {
        WARN( "Unable to find minimum interval for dated story pairs. Using empty story_links" );
        $db->query( "truncate table _dated_story_pairs" );
    }

    # query the pairs of cross-media stories with the shortest time between shares by the same author
    $db->query( <<SQL, $num_stories );
create temporary table snapshot_story_links as
    select stories_id_a source_stories_id, stories_id_b ref_stories_id, min(date_diff) min_date_diff
        from _dated_story_pairs
        group by stories_id_a, stories_id_b
        order by min_date_diff asc limit ?
SQL

    $db->query( <<SQL );
drop table _post_stories;
drop table _dated_story_pairs;
SQL
}

sub _write_story_links_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_story_links" );

    if ( _timespan_is_url_sharing( $db, $timespan ) )
    {
        _create_url_sharing_story_links( $db, $timespan );
    }
    else
    {
        $db->query( <<END );
create temporary table snapshot_story_links as
    select distinct cl.stories_id source_stories_id, cl.ref_stories_id
	    from snapshot_topic_links_cross_media cl
            join snapshot_period_stories sps on ( cl.stories_id = sps.stories_id )
            join snapshot_period_stories rps on ( cl.ref_stories_id = rps.stories_id )
            left join stories_ap_syndicated sap on ( sps.stories_id = sap.stories_id )
    	where
            ( ( sap.ap_syndicated is null ) or ( sap.ap_syndicated = false ) )
END
    }

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'story_links' );
    }
}

sub _write_timespan_posts_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_timespan_posts" ); 

    my $topic_seed_queries_id = _get_timespan_seed_query( $db, $timespan );

    $db->query( <<SQL, $topic_seed_queries_id, $timespan->{ start_date }, $timespan->{ end_date } );
create temporary table snapshot_timespan_posts as
    select distinct topic_posts_id
        from topic_post_stories
        where
            topic_seed_queries_id = ? and
            publish_date >= ? and publish_date < ?
SQL

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'timespan_posts' );
    }
}

sub _write_story_link_counts_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_story_link_counts" );

    $db->query( <<END );
create temporary table snapshot_story_link_counts as
    with  snapshot_story_media_links as (
       select
            s.media_id source_media_id,
            sl.ref_stories_id ref_stories_id
        from
            snapshot_story_links sl
            join snapshot_stories s on ( s.stories_id = sl.source_stories_id )
        group by s.media_id, sl.ref_stories_id
    ),

    snapshot_story_media_link_counts as (
        select
                count(*) media_inlink_count,
                sml.ref_stories_id stories_id
            from
                snapshot_story_media_links sml
            group by sml.ref_stories_id
    ),

    snapshot_post_counts as (
        select
                tps.stories_id,
                count( * ) as post_count,
                count( distinct tp.author ) as author_count,
                count( distinct tp.channel ) as channel_count
            from snapshot_timespan_posts stp
                join topic_post_stories tps using ( topic_posts_id )
                join topic_posts tp using ( topic_posts_id )
            group by tps.stories_id
    )

    select distinct ps.stories_id,
            coalesce( smlc.media_inlink_count, 0 ) media_inlink_count,
            coalesce( ilc.inlink_count, 0 ) inlink_count,
            coalesce( olc.outlink_count, 0 ) outlink_count,
            stc.post_count,
            stc.author_count,
            stc.channel_count,
            ss.facebook_share_count facebook_share_count
        from snapshot_period_stories ps
            left join snapshot_story_media_link_counts smlc using ( stories_id )
            left join
                ( select sl.ref_stories_id,
                         count( distinct sl.source_stories_id ) inlink_count
                  from snapshot_story_links sl,
                       snapshot_period_stories ps
                  where sl.source_stories_id = ps.stories_id
                  group by sl.ref_stories_id
                ) ilc on ( ps.stories_id = ilc.ref_stories_id )
            left join
                ( select sl.source_stories_id stories_id,
                         count( distinct sl.ref_stories_id ) outlink_count
                  from snapshot_story_links sl,
                       snapshot_period_stories ps
                  where sl.ref_stories_id = ps.stories_id
                  group by sl.source_stories_id
                ) olc on ( ps.stories_id = olc.stories_id )
            left join story_statistics ss
                on ss.stories_id = ps.stories_id
            left join snapshot_post_counts stc
                on stc.stories_id = ps.stories_id
END

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'story_link_counts' );
    }
}

sub _write_medium_link_counts_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_medium_link_counts" );

    $db->query( <<END );
create temporary table snapshot_medium_link_counts as

    with medium_media_link_counts as (
       select
            count(*) media_inlink_count,
            dml.ref_media_id media_id
        from
            snapshot_medium_links dml
        group by dml.ref_media_id
    ),

    medium_link_counts as (
        select m.media_id,
               sum( slc.media_inlink_count ) sum_media_inlink_count,
               sum( slc.inlink_count) inlink_count,
               sum( slc.outlink_count) outlink_count,
               count(*) story_count,
               sum( slc.facebook_share_count ) facebook_share_count,
               sum( slc.post_count ) sum_post_count,
               sum( slc.author_count ) sum_author_count,
               sum( slc.channel_count ) sum_channel_count
            from
                snapshot_media m
                join snapshot_stories s using ( media_id )
                join snapshot_story_link_counts slc using ( stories_id )
            where m.media_id = s.media_id and s.stories_id = slc.stories_id
            group by m.media_id
    )

    select
            mlc.*,
            coalesce( mmlc.media_inlink_count, 0 ) media_inlink_count
        from medium_link_counts mlc
            left join medium_media_link_counts mmlc using ( media_id )
END

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'medium_link_counts' );
    }
}

sub _write_medium_links_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_medium_links" );

    $db->query( <<END );
create temporary table snapshot_medium_links as
    select s.media_id source_media_id, r.media_id ref_media_id, count(*) link_count
        from snapshot_story_links sl, snapshot_stories s, snapshot_stories r
        where sl.source_stories_id = s.stories_id and sl.ref_stories_id = r.stories_id
        group by s.media_id, r.media_id
END

    if ( !$is_model )
    {
        _create_timespan_snapshot( $db, $timespan, 'medium_links' );
    }
}

sub _create_timespan($$$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period, $focus ) = @_;

    my $snapshots_id = $cd->{ snapshots_id };
    my $foci_id = $focus ? $focus->{ foci_id } : undef;

    my $focus_clause = $foci_id ? "foci_id = $foci_id" : "foci_id is null";

    my $timespan = $db->query( <<SQL, $snapshots_id, $start_date, $end_date, $period, $foci_id )->hash();
select *
    from timespans
    where
        snapshots_id = \$1 and
        start_date = \$2 and
        end_date = \$3 and
        period = \$4 and
        $focus_clause
SQL

    $timespan ||= $db->query( <<SQL, $snapshots_id, $start_date, $end_date, $period, $foci_id )->hash();
insert into timespans
    ( snapshots_id, start_date, end_date, period, foci_id, 
      story_count, story_link_count, medium_count, medium_link_count, post_count )
    values ( \$1, \$2, \$3, \$4, \$5, 0, 0, 0, 0, 0 )
    returning *
SQL

    $timespan->{ snapshot } = $cd;

    return $timespan;
}

# return true if there exists at least one row in the relevant table for which timespans_id = $timespans_id
sub _timespan_snapshot_exists($$$)
{
    my ( $db, $table, $timespan ) = @_;

    die( "Table name can only have letters and underscores" ) if ( $table =~ /[^a-z_]/i );

    my $exists = $db->query( "select 1 from snap.$table where timespans_id = ?", $timespan->{ timespans_id } )->hash();

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
    MediaWords::JobManager::Job::add_to_queue( 'MediaWords::Job::TM::Map', { timespans_id => $timespans_id } );
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

    ( $timespan->{ story_count } ) = $db->query( "select count(*) from snapshot_story_link_counts" )->flat;

    ( $timespan->{ story_link_count } ) = $db->query( "select count(*) from snapshot_story_links" )->flat;

    ( $timespan->{ medium_count } ) = $db->query( "select count(*) from snapshot_medium_link_counts" )->flat;

    ( $timespan->{ medium_link_count } ) = $db->query( "select count(*) from snapshot_medium_links" )->flat;

    ( $timespan->{ post_count } ) = $db->query( "select count(*) from snapshot_timespan_posts" )->flat;

    return if ( $live );

    for my $field ( qw(story_count story_link_count medium_count medium_link_count) )
    {
        update_timespan( $db, $timespan, $field, $timespan->{ $field } );
    }
}

# generate the snapshot timespans for the given period, dates, and tag
sub _generate_timespan($$$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period, $focus ) = @_;

    my $timespan = _create_timespan( $db, $cd, $start_date, $end_date, $period, $focus );

    my $snapshot_label = "${ period }: ${ start_date } - ${ end_date } ";
    $snapshot_label .= "[ $focus->{ name } ]" if ( $focus );

    DEBUG( "generating $snapshot_label ..." );

    _update_job_state_message( $db, "snapshotting $snapshot_label" );

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
sub _generate_custom_period_snapshot ($$$ )
{
    my ( $db, $cd, $focus ) = @_;

    my $topic_dates = $db->query( <<END, $cd->{ topics_id } )->hashes;
select * from topic_dates where topics_id = ? order by start_date, end_date
END

    for my $topic_date ( @{ $topic_dates } )
    {
        my $start_date = $topic_date->{ start_date };
        my $end_date   = $topic_date->{ end_date };
        _generate_timespan( $db, $cd, $start_date, $end_date, 'custom', $focus );
    }
}

# generate snapshot for the given period (overall, monthly, weekly, or custom) and the given tag
sub _generate_period_snapshot($$$$)
{
    my ( $db, $cd, $period, $focus ) = @_;

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
        _generate_custom_period_snapshot( $db, $cd, $focus );
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

    my $snapshot_exists = $db->query( "select 1 from snap.$table where $key = $obj->{ $key }" )->hash();
    if ( $snapshot_exists )
    {
        DEBUG( "snapshot $table already exists.  skipping ..." );
        return;
    }

    my $column_names = [ $db->query( <<END, $table, $key )->flat ];
select column_name from information_schema.columns
    where table_name = ? and table_schema = 'snap' and
        column_name not in ( ? )
    order by ordinal_position asc
END

    die( "Field names can only have letters and underscores" ) if ( grep { /[^a-z_]/i } @{ $column_names } );

    my $column_list = join( ",", @{ $column_names } );

    $db->query( <<END, $obj->{ $key } );
insert into snap.${ table } ( $column_list, $key ) select $column_list, ? from snapshot_${ table }
END

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

    $db->query( "create temporary table snapshot_stories_tags_map as select * from stories_tags_map limit 0" );

    $db->query( <<SQL, $snapshot->{ snapshots_id } );
insert into snapshot_stories_tags_map ( stories_id, tags_id )
    select stories_id, tags_id from snap.stories_tags_map where snapshots_id = ?
SQL
    
    my $new_stories_ids = $db->query( <<SQL )->flat;
select stories_id from snapshot_stories where stories_id not in (
    select stories_id from snapshot_stories_tags_map )
SQL

    for my $new_stories_id ( @{ $new_stories_ids } )
    {
        my $tags_ids = $db->query( "select tags_id from stories_tags_map where stories_id = ?", $new_stories_id )->flat;
        return unless @{ $tags_ids };

        my $values_list = join( ',', map { "($new_stories_id, $_)" } @{ $tags_ids } );

        $db->query( "insert into snapshot_stories_tags_map ( stories_id, tags_id ) values $values_list" );
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
        $db->query( <<SQL, $topic->{ topics_id } );
create temporary table snapshot_topic_stories as
    select cs.*
        from topic_stories cs
        where cs.topics_id = ?
SQL
    }
    else
    {
        $db->query( <<SQL, $topic->{ topics_id } );
create temporary table snapshot_topic_stories as 

with link_stories as (
    select ts.stories_id
        from topic_links tl
            join topic_stories ts on ( ts.stories_id = tl.ref_stories_id and ts.topics_id = tl.topics_id )
        where
            tl.topics_id = \$1
),

fb_stories as (
    select ss.stories_id
        from topic_stories ts
            join story_statistics ss using ( stories_id )
        where
            ts.topics_id = \$1 and
            ss.facebook_share_count >= 100
),

post_stories as (
    select ts.stories_id
        from topic_stories ts
        where 
            ts.topics_id = \$1 and
            exists (select 1 from snap.story_link_counts where stories_id = ts.stories_id and post_count >= 10)
)

select ts.*
    from topic_stories ts
    where
        topics_id = \$1 and
        stories_id in ( 
            select stories_id from link_stories  union
            select stories_id from fb_stories union
            select stories_id from post_stories
        )
SQL
    }
}

# generate temporary snapshot_* tables for the specified snapshot for each of the snapshot_tables.
# these are the tables that apply to the whole snapshot.
sub _write_temporary_snapshot_tables($$$)
{
    my ( $db, $topic, $snapshot ) = @_;

    my $topics_id = $topic->{ topics_id };

    _create_snapshot_topic_stories( $db, $topic );

    $db->query( <<END, $topics_id );
create temporary table snapshot_topic_media_codes as
    select cmc.*
        from topic_media_codes cmc
        where cmc.topics_id = ?
END

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
                JOIN snapshot_topic_stories AS dcs
                    ON s.stories_id = dcs.stories_id
                   AND s.topics_id = ?
SQL
        $topics_id
    );

    $db->query( <<END );
create temporary table snapshot_media as
    select m.* from media m
        where m.media_id in ( select media_id from snapshot_stories )
END

    $db->query( <<END, $topics_id );
create temporary table snapshot_topic_links_cross_media as
    select s.stories_id, r.stories_id ref_stories_id, cl.url, cs.topics_id, cl.topic_links_id
        from topic_links cl
            join snapshot_topic_stories cs on ( cs.stories_id = cl.ref_stories_id )
            join snapshot_stories s on ( cl.stories_id = s.stories_id )
            join snapshot_media sm on ( s.media_id = sm.media_id )
            join snapshot_stories r on ( cl.ref_stories_id = r.stories_id )
            join snapshot_media rm on ( r.media_id= rm.media_id )
        where cl.topics_id = ? and r.media_id <> s.media_id
END


    _create_snapshot_stories_tags_map( $db, $snapshot );

    $db->query( <<END );
create temporary table snapshot_media_tags_map as
    select mtm.*
    from media_tags_map mtm, snapshot_media dm
    where mtm.media_id = dm.media_id
END

    my $tweet_topics_id = $topic->{ topics_id };

    my $bot_clause = '';
    my $bot_policy = $snapshot->{ bot_policy } || $POLICY_NO_BOTS;
    if ( $bot_policy eq $POLICY_NO_BOTS )
    {
        $bot_clause = "and ( ( coalesce( tweets, 0 ) / coalesce( days, 1 ) ) < $BOT_TWEETS_PER_DAY )";
    }
    elsif ( $bot_policy eq $POLICY_ONLY_BOTS )
    {
        $bot_clause = "and ( ( coalesce( tweets, 0 ) / coalesce( days, 1 ) ) >= $BOT_TWEETS_PER_DAY )";
    }

    MediaWords::TM::Snapshot::Views::add_media_type_views( $db );

    for my $table ( @{ MediaWords::TM::Snapshot::Views::get_snapshot_tables() } )
    {
        my $table_exists = $db->query( "select * from pg_class where relname = 'snapshot_' || ?", $table )->hash;
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

# create focal_set and foci for all of the url sharing platforms present in seed queries for the topic. return foci.
sub _create_url_sharing_foci
{
    my ( $db, $snapshot ) = @_;

    my $focal_set = {
        snapshots_id => $snapshot->{ snapshots_id },
        name => $TECHNIQUE_SHARING,
        description => 'Subtopics for analysis of url cosharing on urls collected by platform seed queries.',
        focal_technique =>  'URL Sharing'
    };
    $focal_set = $db->find_or_create( 'focal_sets', $focal_set );

    my $tsqs = $db->query( "select * from topic_seed_queries where topics_id = ?", $snapshot->{ topics_id } )->hashes;

    my $foci = [];
    for my $tsq ( @{ $tsqs } )
    {
        next unless ( grep { $tsq->{ platform } eq $_ } @{ $URL_SHARING_PLATFORMS } );

        my $focal_sets_id = $focal_set->{ focal_sets_id };
        my $topic_seed_queries_id = $tsq->{ topic_seed_queries_id };

        my $existing_focus = $db->query( <<SQL, $focal_sets_id, $topic_seed_queries_id )->hash;
select * from foci where focal_sets_id = ? and ( arguments->>'topic_seed_queries_id' )::int = ?::int        
SQL
        if ( !$existing_focus )
        {
            my $arguments = { mode => 'url_sharing', topic_seed_queries_id => $topic_seed_queries_id };

            my $focus = {
                focal_sets_id => $focal_sets_id,
                name => "$tsq->{ platform } [$tsq->{ topic_seed_queries_id }]",
                description => "Subtopic for analysis of url cosharing on urls collected from $tsq->{ platform }",
                arguments => MediaWords::Util::ParseJSON::encode_json( $arguments )
            };
            $focus = $db->create( 'foci', $focus );
            push( @{ $foci }, $focus );
        }
    }

    return $foci;
}

# generate period spanshots for each period / focus / timespan combination
sub _generate_period_focus_snapshots ( $$$ )
{
    my ( $db, $snapshot, $periods ) = @_;

    my $sharing_foci = _create_url_sharing_foci( $db, $snapshot );

    for my $focus ( @{ $sharing_foci } )
    {
        map { _generate_period_snapshot( $db, $snapshot, $_, $focus ) } @{ $periods };
    }

    my $fsds = $db->query( <<SQL, $snapshot->{ topics_id }, $TECHNIQUE_BOOLEAN )->hashes;
select * from focal_set_definitions where topics_id = ? and focal_technique = ?
SQL

    for my $fsd ( @{ $fsds } )
    {
        my $focal_set = $db->query( <<SQL, $fsd->{ focal_set_definitions_id }, $snapshot->{ snapshots_id } )->hash;
insert into focal_sets ( name, description, focal_technique, snapshots_id )
    select name, description, focal_technique, \$2 from focal_set_definitions where focal_set_definitions_id = \$1
    on conflict (snapshots_id, name) do update set snapshots_id = \$2
    returning *
SQL

        my $fds = $db->query( <<SQL, $fsd->{ focal_set_definitions_id } )->hashes;
select * from focus_definitions where focal_set_definitions_id = \$1
SQL

        for my $fd ( @{ $fds } )
        {
            my $focus = $db->query( <<SQL, $fd->{ focus_definitions_id }, $focal_set->{ focal_sets_id } )->hash;
insert into foci ( name, description, arguments, focal_sets_id )
    select name, description, arguments, \$2 from focus_definitions where focus_definitions_id = \$1
    on conflict ( focal_sets_id, name ) do update set focal_sets_id = \$2
    returning *
SQL
            map { _generate_period_snapshot( $db, $snapshot, $_, $focus ) } @{ $periods };
        }
    }
}

# put all stories in this dump in solr_extra_import_stories for export to solr
sub _export_stories_to_solr($$)
{
    my ( $db, $cd ) = @_;

    DEBUG( "queueing stories for solr import ..." );
    $db->query( <<SQL, $cd->{ snapshots_id } );
insert into solr_import_stories ( stories_id )
    select distinct stories_id from snap.stories where snapshots_id = ?
SQL

    $db->update_by_id( 'snapshots', $cd->{ snapshots_id }, { searchable => 'f' } );
}

# die if each of the $periods is not among the $allowed_periods
sub _validate_periods($$)
{
    my ( $periods, $allowed_periods ) = @_;

    for my $period ( @{ $allowed_periods } )
    {
        die( "unknown period: '$period'" ) unless ( grep { $period eq $_ } @{ $allowed_periods } );
    }
}

# Create a snapshot for the given topic.  Optionally pass a note and/or a bot_policy field to the created snapshot.
#
# The bot_policy should be one of 'all', 'no bots', or 'only bots' indicating for twitter topics whether and how to
# filter for bots (a bot is defined as any user tweeting more than 200 post per day).
#
# The periods should be a list of periods to include in the snapshot, where the allowed periods are custom,
# overall, weekly, and monthly.  If periods is not specificied or is empty, all periods will be generated.
#
# If a snapshots_id is provided, use the existing snapshot.  Otherwise, create a new one.
#
# Returns snapshots_id of the provided or newly created snapshot.
sub snapshot_topic ($$;$$$$)
{
    my ( $db, $topics_id, $snapshots_id, $note, $bot_policy, $periods ) = @_;

    my $allowed_periods = [ qw(custom overall weekly monthly) ];

    $periods = $allowed_periods if ( !$periods || !@{ $periods } );

    _validate_periods( $periods, $allowed_periods );

    my $topic = $db->require_by_id( 'topics', $topics_id );

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
      : MediaWords::DBI::Snapshots::create_snapshot_row( $db, $topic, $start_date, $end_date, $note, $bot_policy );

    _update_job_state_args( $db, { snapshots_id => $snap->{ snapshots_id } } );
    _update_job_state_message( $db, "snapshotting data" );

    _write_temporary_snapshot_tables( $db, $topic, $snap );

    _generate_snapshots_from_temporary_snapshot_tables( $db, $snap );

    # generate null focus timespan snapshots
    map { _generate_period_snapshot( $db, $snap, $_, undef ) } ( @{ $periods } );

    _generate_period_focus_snapshots( $db, $snap, $periods );

    _update_job_state_message( $db, "finalizing snapshot" );

    _export_stories_to_solr( $db, $snap );

    MediaWords::TM::Snapshot::Views::discard_temp_tables_and_views( $db );

    # update this manually because snapshot_topic might be called directly from mine_topic()
    $db->update_by_id( 'snapshots', $snap->{ snapshots_id }, { state => $MediaWords::JobManager::AbstractStatefulJob::STATE_COMPLETED } );
    MediaWords::TM::Alert::send_topic_alert( $db, $topic, "new topic snapshot is ready" );

    return $snap->{ snapshots_id };
}

1;
