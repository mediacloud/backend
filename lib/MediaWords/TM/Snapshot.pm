package MediaWords::TM::Snapshot;

=head1 NAME

MediaWords::TM::Snapshot - Snapshot and analyze topic data

=head1 SYNOPSIS

    # generate a new topic snapshot -- this is run via snapshot_topic.pl once or each snapshot
    snapshot_topic( $db, $topics_id );

    # the rest of these examples are run each time we want to query topic data

    # setup and query snapshot tables
    my $live = 1;
    MediaWords::TM::Snapshot::create_temporary_snapshot_views( $db, $timespan );

    # query data
    my $story_links = $db->query( "select * from snapshot_story_links" )->hashes;
    my $story_link_counts = $db->query( "select * from story_link_counts" )->hashes;
    my $snapshot_stories = $db->query( "select * from snapshot_stories" )->hashes;

    # get csv snapshot
    my $media_csv = MediaWords::TM::Snapshot::get_media_csv( $db, $timespan );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

=head1 DESCRIPTION

Analyze a topic and snapshot the topic to snapshot tables and a gexf file.

For detailed explanation of the snapshot process, see doc/snapshots.markdown.

=cut

# This module was converted from a script, and the functions were never refactored to prefix private methods with '_'.
# Consider any method without a perldoc head to be private.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Date::Format;
use Encode;
use File::Temp;
use FileHandle;
use Getopt::Long;
use List::Util;
use XML::Simple;
use Readonly;

use MediaWords::DBI::Media;
use MediaWords::Job::TM::SnapshotTopic;
use MediaWords::Solr::Query;
use MediaWords::TM;
use MediaWords::TM::Model;
use MediaWords::TM::Snapshot::GraphLayout;
use MediaWords::Util::CSV;
use MediaWords::Util::Colors;
use MediaWords::Util::Config;
use MediaWords::Util::Paths;
use MediaWords::Util::SQL;
use MediaWords::DBI::Activities;

# possible values of snapshots.bot_policy
Readonly our $POLICY_NO_BOTS   => 'no bots';
Readonly our $POLICY_ONLY_BOTS => 'only bots';
Readonly our $POLICY_BOTS_ALL  => 'all';

# max and mind node sizes for gexf snapshot
Readonly my $MAX_NODE_SIZE => 20;
Readonly my $MIN_NODE_SIZE => 2;

# max map width for gexf snapshot
Readonly my $MAX_MAP_WIDTH => 800;

# max number of media to include in gexf map
Readonly my $MAX_GEXF_MEDIA => 500;

# number of tweets per day to use as a threshold for bot filtering
Readonly my $BOT_TWEETS_PER_DAY => 200;

# only layout the gexf export if there are fewer than this number of sources in the graph
Readonly my $MAX_LAYOUT_SOURCES => 2000;

# attributes to include in gexf snapshot
my $_media_static_gexf_attribute_types = {
    url                    => 'string',
    inlink_count           => 'integer',
    story_count            => 'integer',
    view_medium            => 'string',
    media_type             => 'string',
    facebook_share_count   => 'integer',
    simple_tweet_count     => 'integer',
    normalized_tweet_count => 'integer'
};

# all tables that get stored as snapshot_* for each spanshot
my $_snapshot_tables = [
    qw/topic_stories topic_links_cross_media topic_media_codes
      stories media stories_tags_map media_tags_map tags tag_sets tweet_stories/
];

# all tables that get stories as snapshot_* for each timespan
my $_timespan_tables = [ qw/story_link_counts story_links medium_link_counts medium_links timespan_tweets/ ];

# tablespace clause for temporary tables
my $_temporary_tablespace;

# temporary hack to get around snapshot_period_stories lock
my $_drop_snapshot_period_stories = 1;

=head1 FUNCTIONS

=cut

# get the list of all snapshot tables
sub __get_snapshot_tables
{
    return [ @{ $_snapshot_tables } ];
}

# get the list of all timespan specific tables
sub get_timespan_tables
{
    return [ @{ $_timespan_tables } ];
}

# if the temporary_table_tablespace config is present, set $_temporary_tablespace
# to a tablespace clause for the tablespace, otherwise set it to ''
sub set_temporary_table_tablespace
{
    my $config = MediaWords::Util::Config::get_config;

    my $tablespace = $config->{ mediawords }->{ temporary_table_tablespace };

    $_temporary_tablespace = $tablespace ? "tablespace $tablespace" : '';
}

# create temporary view of all the snapshot_* tables that call into the snap.* tables.
# this is useful for writing queries on the snap.* tables without lots of ugly
# joins and clauses to cd and timespan.  It also provides the same set of snapshot_*
# tables as provided by write_story_link_counts_snapshot_tables, so that the same
# set of queries can run against either.
sub create_temporary_snapshot_views($$)
{
    my ( $db, $timespan ) = @_;

    # postgres prints lots of 'NOTICE's when deleting temp tables
    $db->set_print_warn( 0 );

    for my $t ( @{ __get_snapshot_tables() } )
    {
        $db->query(
            <<SQL
            CREATE TEMPORARY VIEW snapshot_$t AS
                SELECT *
                FROM snap.$t
                WHERE snapshots_id = $timespan->{ snapshots_id }
SQL
        );
    }

    for my $t ( @{ get_timespan_tables() } )
    {
        $db->query(
            <<SQL
            CREATE TEMPORARY VIEW snapshot_$t AS
                SELECT *
                FROM snap.$t
                WHERE timespans_id = $timespan->{ timespans_id }
SQL
        );
    }

    $db->query(
        <<SQL
        CREATE TEMPORARY VIEW snapshot_period_stories AS
            SELECT stories_id
            FROM snapshot_story_link_counts
SQL
    );

    add_media_type_views( $db );

    # Set the warnings back on
    $db->set_print_warn( 0 );
}

=head2 discard_temp_tables( $db )

Runs $db->query( "discard temp" ) to clean up temporary tables and views.  This should be run after calling
create_temporary_snapshot_views().  Calling create_temporary_snapshot_views() within a transaction and committing the
transaction will have the same effect.

=cut

sub discard_temp_tables
{
    my ( $db ) = @_;

    $db->query( "discard temp" );
}

# remove stories from snapshot_period_stories that don't math solr query in the associated focus, if any
sub restrict_period_stories_to_focus
{
    my ( $db, $timespan ) = @_;

    return unless ( $timespan->{ foci_id } );

    my $qs = $db->query( "select *, arguments->>'query' query from foci where foci_id = ?", $timespan->{ foci_id } )->hash;

    my $snapshot_period_stories_ids = $db->query( "select stories_id from snapshot_period_stories" )->flat;

    if ( !@{ $snapshot_period_stories_ids } )
    {
        $db->query( "truncate table snapshot_period_stories" );
        return;

    }
    my $all_stories_ids      = [ @{ $snapshot_period_stories_ids } ];
    my $matching_stories_ids = [];
    my $chunk_size           = 1000;
    my $min_chunk_size       = 10;
    my $max_solr_errors      = 25;
    my $solr_error_count     = 0;

    while ( @{ $all_stories_ids } )
    {
        my $chunk_stories_ids = [];
        my $chunk_size = List::Util::min( $chunk_size, scalar( @{ $all_stories_ids } ) );
        map { push( @{ $chunk_stories_ids }, shift( @{ $all_stories_ids } ) ) } ( 1 .. $chunk_size );

        my $solr_q = $qs->{ query };

        die( "focus boolean query '$solr_q' must include non-space character" ) unless ( $solr_q =~ /[^[:space:]]/ );

        my $stories_ids_list = join( ' ', @{ $chunk_stories_ids } );
        $solr_q = "( $solr_q ) and stories_id:( $stories_ids_list )";

        my $solr_stories_ids =
          eval { MediaWords::Solr::Query::search_for_stories_ids( $db, { rows => 1000000, q => $solr_q } ) };
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

    my $ids_table = $db->get_temporary_ids_table( $matching_stories_ids );

    $db->query( "delete from snapshot_period_stories where stories_id not in ( select id from $ids_table )" );
}

# get the where clause that will restrict the snapshot_period_stories creation
# to only stories within the timespan time frame
sub get_period_stories_date_where_clause
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

# for a twitter topic, the only stories that should appear in the timespan are stories associated
# with a tweet published during the timespan
sub create_twitter_snapshot_period_stories($$)
{
    my ( $db, $timespan ) = @_;

    $db->query( <<SQL, $timespan->{ timespans_id } );
create temporary table snapshot_period_stories $_temporary_tablespace as
    select distinct stories_id
        from snapshot_tweet_stories ts
            join timespans t on ( timespans_id = \$1 )
        where
            ts.publish_date between t.start_date and t.end_date
SQL
}

# restrict the set of stories to the current timespan based on publish date or referencing story
# publish date.  a story should be in the current snapshot if either its date is within
# the period dates or if a story that links to it has a date within the period dates.
# For this purpose, stories tagged with the 'date_invalid:undateable' tag
# are considered to have an invalid tag, so their dates cannot be used to pass
# either of the above tests.
sub create_link_snapshot_period_stories($$)
{
    my ( $db, $timespan ) = @_;

    $db->query( <<END );
create or replace temporary view snapshot_undateable_stories as
select distinct s.stories_id
    from snapshot_stories s, snapshot_stories_tags_map stm, snapshot_tags t, snapshot_tag_sets ts
    where s.stories_id = stm.stories_id and
        stm.tags_id = t.tags_id and
        t.tag_sets_id = ts.tag_sets_id and
        ts.name = 'date_invalid' and
        t.tag = 'undateable'
END

    my $date_where_clause = get_period_stories_date_where_clause( $timespan );

    $db->query( <<"END", $timespan->{ start_date }, $timespan->{ end_date } );
create temporary table snapshot_period_stories $_temporary_tablespace as
select distinct s.stories_id
    from snapshot_stories s
        left join snapshot_topic_links_cross_media cl on ( cl.ref_stories_id = s.stories_id )
        left join snapshot_stories ss on ( cl.stories_id = ss.stories_id )
    where
        $date_where_clause
END

    $db->query( "drop view snapshot_undateable_stories" );
}

# return true if the topic of the timespan is a twitter_topic
sub topic_is_twitter_topic
{
    my ( $db, $timespan ) = @_;

    my ( $is_twitter_topic ) = $db->query( <<SQL, $timespan->{ snapshots_id } )->flat;
select 1
    from topics t
        join snapshots s using ( topics_id )
    where
        t.ch_monitor_id is not null and
        s.snapshots_id = \$1
SQL

    $is_twitter_topic ||= 0;

    return $is_twitter_topic;
}

# write snapshot_period_stories table that holds list of all stories that should be included in the
# current period.  For an overall snapshot, every story should be in the current period.
# the definition of period stories depends on whether the topic is a twitter topic or not.
#
# The resulting snapshot_period_stories should be used by all other snapshot queries to determine
# story membership within a give period.
sub write_period_stories
{
    my ( $db, $timespan ) = @_;

    $db->query( "drop table if exists snapshot_period_stories" );

    if ( !$timespan || ( $timespan->{ period } eq 'overall' ) )
    {
        $db->query( <<END );
create temporary table snapshot_period_stories $_temporary_tablespace as select stories_id from snapshot_stories
END
    }
    elsif ( topic_is_twitter_topic( $db, $timespan ) )
    {
        create_twitter_snapshot_period_stories( $db, $timespan );
    }
    else
    {
        create_link_snapshot_period_stories( $db, $timespan );
    }

    my ( $num_period_stories ) = $db->query( "select count(*) from snapshot_period_stories" )->flat;
    DEBUG( "num_period_stories: $num_period_stories" );

    if ( $timespan->{ foci_id } )
    {
        restrict_period_stories_to_focus( $db, $timespan );
    }
}

sub create_snap_file
{
    my ( $db, $cd, $file_name, $file_content ) = @_;

    my $snap_file = {
        snapshots_id => $cd->{ snapshots_id },
        file_name    => $file_name,
        file_content => $file_content
    };

    return $db->create( 'snap_files', $snap_file );
}

# convenience function to update a field in the timespan table
sub update_timespan
{
    my ( $db, $timespan, $field, $val ) = @_;

    $db->update_by_id( 'timespans', $timespan->{ timespans_id }, { $field => $val } );
}

=head2 get_story_links_csv( $db, $timespan )

Get an encoded csv snapshot of the story links for the given timespan.

=cut

sub get_story_links_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select distinct sl.source_stories_id source_stories_id, ss.title source_title, ss.url source_url,
        sm.name source_media_name, sm.url source_media_url, sm.media_id source_media_id,
		sl.ref_stories_id ref_stories_id, rs.title ref_title, rs.url ref_url, rm.name ref_media_name, rm.url ref_media_url,
		rm.media_id ref_media_id
	from snapshot_story_links sl, snap.live_stories ss, media sm, snap.live_stories rs, media rm
	where sl.source_stories_id = ss.stories_id and
	    ss.media_id = sm.media_id and
	    sl.ref_stories_id = rs.stories_id and
	    rs.media_id = rm.media_id
END

    return $csv;
}

sub write_story_links_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_story_links" );

    if ( topic_is_twitter_topic( $db, $timespan ) )
    {
        $db->execute_with_large_work_mem(
            <<SQL
create temporary table snapshot_story_links as

    with tweet_stories as (
        select s.media_id, s.stories_id, s.twitter_user, s.publish_date
            from snapshot_tweet_stories s
                join snapshot_timespan_tweets t using ( topic_tweets_id )
    ),

    coshared_links as (
        select
                a.stories_id stories_id_a, a.twitter_user, b.stories_id stories_id_b
            from
                tweet_stories a
                join tweet_stories b using ( twitter_user )
            where
                a.media_id <> b.media_id and
                date_trunc( 'day', a.publish_date ) = date_trunc( 'day', b.publish_date )
            group by a.stories_id, b.stories_id, a.twitter_user
    )

    select cs.stories_id_a source_stories_id, cs.stories_id_b ref_stories_id
        from coshared_links cs
        group by cs.stories_id_a, cs.stories_id_b
SQL
        );
    }
    else
    {
        $db->query( <<END );
create temporary table snapshot_story_links $_temporary_tablespace as
    select distinct cl.stories_id source_stories_id, cl.ref_stories_id
	    from snapshot_topic_links_cross_media cl
            join snapshot_period_stories sps on ( cl.stories_id = sps.stories_id )
            join snapshot_period_stories rps on ( cl.ref_stories_id = rps.stories_id )
            left join stories_ap_syndicated sap on ( sps.stories_id = sap.stories_id )
    	where
            ( ( sap.ap_syndicated is null ) or ( sap.ap_syndicated = false ) )
END
    }

    # re-enable above to prevent post-dated links
    #          ss.publish_date > rs.publish_date - interval '1 day' and

    if ( !$is_model )
    {
        create_timespan_snapshot( $db, $timespan, 'story_links' );
    }
}

=head2 get_stories_csv( $db, $timespan )

Get an encoded csv snapshot of the stories inr the given timespan.

=cut

sub get_stories_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select s.stories_id, s.title, s.url,
        case when ( stm.tags_id is null ) then s.publish_date::text else 'undateable' end as publish_date,
        m.name media_name, m.url media_url, m.media_id,
        slc.media_inlink_count, slc.inlink_count, slc.outlink_count, slc.facebook_share_count,
        slc.simple_tweet_count, slc.normalized_tweet_count
	from snapshot_stories s
	    join snapshot_media m on ( s.media_id = m.media_id )
	    join snapshot_story_link_counts slc on ( s.stories_id = slc.stories_id )
	    left join (
	        snapshot_stories_tags_map stm
                join tags t on ( stm.tags_id = t.tags_id  and t.tag = 'undateable' )
                join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id and ts.name = 'date_invalid' ) )
            on ( stm.stories_id = s.stories_id )
	order by slc.media_inlink_count desc
END

    return $csv;
}

sub get_timespan_tweets_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<SQL );
select tt.topic_tweets_id, tt.tweet_id, tt.publish_date, tt.twitter_user, tt.data->>'url' url, tt.content
    from snap.timespan_tweets stt
        join topic_tweets tt using ( topic_tweets_id )
SQL
}

sub write_timespan_tweets_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_timespan_tweets" );

    my $start_date_q = $db->quote( $timespan->{ start_date } );
    my $end_date_q   = $db->quote( $timespan->{ end_date } );

    my $date_clause =
      $timespan->{ period } eq 'overall'
      ? '1=1'
      : "publish_date between $start_date_q and $end_date_q";

    my $snapshot = $db->require_by_id( 'snapshots', $timespan->{ snapshots_id } );
    my $topic    = $db->require_by_id( 'topics',    $snapshot->{ topics_id } );

    $db->query( <<SQL );
create temporary table snapshot_timespan_tweets as
    select distinct ts.topic_tweets_id
        from snapshot_tweet_stories ts
            join snapshot_period_stories s using ( stories_id )
            join snapshot_media m using ( media_id )
        where
            m.url not like '%twitter.com%' and
            $date_clause
SQL

    if ( !$is_model )
    {
        create_timespan_snapshot( $db, $timespan, 'timespan_tweets' );
    }
}

sub write_story_link_counts_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_story_link_counts" );

    $db->query( <<END );
create temporary table snapshot_story_link_counts $_temporary_tablespace as
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

    snapshot_twitter_counts as (
        select
                s.stories_id,
                count( distinct ts.twitter_user ) as simple_tweet_count,
                sum( ( num_ch_tweets::float + 1 ) / ( tweet_count + 1 ) ) as normalized_tweet_count
            from snapshot_tweet_stories ts
                join snapshot_period_stories s using ( stories_id )
                join snapshot_timespan_tweets tt using ( topic_tweets_id )
            group by s.stories_id
    )

    select distinct ps.stories_id,
            coalesce( smlc.media_inlink_count, 0 ) media_inlink_count,
            coalesce( ilc.inlink_count, 0 ) inlink_count,
            coalesce( olc.outlink_count, 0 ) outlink_count,
            stc.simple_tweet_count,
            stc.normalized_tweet_count,
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
            left join snapshot_twitter_counts stc
                on stc.stories_id = ps.stories_id
END

    if ( !$is_model )
    {
        create_timespan_snapshot( $db, $timespan, 'story_link_counts' );
    }
}

sub add_partisan_code_to_snapshot_media
{
    my ( $db, $timespan, $media ) = @_;

    my $label = 'partisan_code';

    my $partisan_tags = $db->query( <<END )->hashes;
select dmtm.*, dt.tag
    from snapshot_media_tags_map dmtm
        join snapshot_tags dt on ( dmtm.tags_id = dt.tags_id )
        join snapshot_tag_sets dts on ( dts.tag_sets_id = dt.tag_sets_id )
    where
        dts.name = 'collection' and
        dt.tag like 'partisan_2012_%'
END

    my $map = {};
    map { $map->{ $_->{ media_id } } = $_->{ tag } } @{ $partisan_tags };

    map { $_->{ $label } = $map->{ $_->{ media_id } } || 'null' } @{ $media };

    return $label;
}

sub add_partisan_retweet_to_snapshot_media
{
    my ( $db, $timespan, $media ) = @_;

    my $label = 'partisan_retweet';

    my $partisan_tags = $db->query( <<END )->hashes;
select dmtm.*, dt.tag
    from snapshot_media_tags_map dmtm
        join snapshot_tags dt on ( dmtm.tags_id = dt.tags_id )
        join snapshot_tag_sets dts on ( dts.tag_sets_id = dt.tag_sets_id )
    where
        dts.name = 'retweet_partisanship_2016_count_10'
END

    my $map = {};
    map { $map->{ $_->{ media_id } } = $_->{ tag } } @{ $partisan_tags };

    map { $_->{ $label } = $map->{ $_->{ media_id } } || 'null' } @{ $media };

    return $label;
}

sub add_fake_news_to_snapshot_media
{
    my ( $db, $timespan, $media ) = @_;

    my $label = 'fake_news';

    my $tags = $db->query( <<END )->hashes;
select dmtm.*, dt.tag
    from snapshot_media_tags_map dmtm
        join snapshot_tags dt on ( dmtm.tags_id = dt.tags_id )
        join snapshot_tag_sets dts on ( dts.tag_sets_id = dt.tag_sets_id )
    where
        dts.name = 'collection' and
        dt.tag = 'fake_news_20170112'
END

    my $map = {};
    map { $map->{ $_->{ media_id } } = $_->{ tag } ? 1 : 0 } @{ $tags };

    map { $_->{ $label } = $map->{ $_->{ media_id } } || 0 } @{ $media };

    return $label;
}

# add tags, codes, partisanship and other extra data to all snapshot media for the purpose
# of making a gexf or csv snapshot.  return the list of extra fields added.
sub add_extra_fields_to_snapshot_media
{
    my ( $db, $timespan, $media ) = @_;

    my $partisan_field = add_partisan_code_to_snapshot_media( $db, $timespan, $media );
    my $partisan_retweet_field = add_partisan_retweet_to_snapshot_media( $db, $timespan, $media );
    my $fake_news_field = add_fake_news_to_snapshot_media( $db, $timespan, $media );

    my $all_fields = [ $partisan_field, $partisan_retweet_field, $fake_news_field ];

    map { $_media_static_gexf_attribute_types->{ $_ } = 'string'; } @{ $all_fields };

    return $all_fields;
}

=head2 get_media_csv( $db, $timespan )

Get an encoded csv snapshot of the media in the given timespan.

=cut

sub get_media_csv
{
    my ( $db, $timespan ) = @_;

    my $res = $db->query( <<END );
select m.name, m.url, mlc.*
    from snapshot_media m, snapshot_medium_link_counts mlc
    where m.media_id = mlc.media_id
    order by mlc.media_inlink_count desc;
END

    my $fields = $res->columns;
    my $media  = $res->hashes;

    my $extra_fields = add_extra_fields_to_snapshot_media( $db, $timespan, $media );

    push( @{ $fields }, @{ $extra_fields } );

    my $csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $media, $fields );

    return $csv;
}

sub write_medium_link_counts_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_medium_link_counts" );

    $db->query( <<END );
create temporary table snapshot_medium_link_counts $_temporary_tablespace as

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
               sum( slc.simple_tweet_count ) simple_tweet_count,
               sum( slc.normalized_tweet_count ) normalized_tweet_count
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
        create_timespan_snapshot( $db, $timespan, 'medium_link_counts' );
    }
}

=head2 get_medium_links_csv( $db, $timespan )

Get an encoded csv snapshot of the medium_links in the given timespan.

=cut

sub get_medium_links_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select ml.source_media_id, sm.name source_name, sm.url source_url,
        ml.ref_media_id, rm.name ref_name, rm.url ref_url, ml.link_count
    from snapshot_medium_links ml, media sm, media rm
    where ml.source_media_id = sm.media_id and ml.ref_media_id = rm.media_id
END

    return $csv;
}

sub write_medium_links_snapshot
{
    my ( $db, $timespan, $is_model ) = @_;

    $db->query( "drop table if exists snapshot_medium_links" );

    $db->query( <<END );
create temporary table snapshot_medium_links $_temporary_tablespace as
    select s.media_id source_media_id, r.media_id ref_media_id, count(*) link_count
        from snapshot_story_links sl, snapshot_stories s, snapshot_stories r
        where sl.source_stories_id = s.stories_id and sl.ref_stories_id = r.stories_id
        group by s.media_id, r.media_id
END

    if ( !$is_model )
    {
        create_timespan_snapshot( $db, $timespan, 'medium_links' );
    }
}

sub attach_stories_to_media
{
    my ( $stories, $media ) = @_;

    my $media_lookup = {};
    map { $media_lookup->{ $_->{ media_id } } = $_ } @{ $media };
    map { push( @{ $media_lookup->{ $_->{ media_id } }->{ stories } }, $_ ) } @{ $stories };
}

# return only the $edges that are within the giant component of the network
sub trim_to_giant_component($)
{
    my ( $edges ) = @_;

    my $edge_pairs = [ map { [ $_->{ source }, $_->{ target } ] } @{ $edges } ];

    my $trimmed_edges = MediaWords::TM::Snapshot::GraphLayout::giant_component( $edge_pairs );

    my $edge_lookup = {};
    map { $edge_lookup->{ $_->[ 0 ] }->{ $_->[ 1 ] } = 1 } @{ $trimmed_edges };

    my $links = [ grep { $edge_lookup->{ $_->{ source } }->{ $_->{ target } } } @{ $edges } ];

    DEBUG( "trim_to_giant_component: " . scalar( @{ $edges } ) . " -> " . scalar( @{ $links } ) );

    return $links;
}

sub get_weighted_edges
{
    my ( $db, $media, $options ) = @_;

    my $max_media            = $options->{ max_media };
    my $include_weights      = $options->{ include_weights } || 0;
    my $max_links_per_medium = $options->{ max_links_per_medium } || 1_000_000;

    DEBUG(
"get_weighted_edges: $max_media max media; $include_weights include_weights; $max_links_per_medium max_links_per_medium"
    );

    my $media_links = $db->query( <<END, $max_media, $max_links_per_medium )->hashes;
with top_media as (
    select * from snapshot_medium_link_counts order by media_inlink_count desc limit \$1
),

ranked_media as (
    select *,
            row_number() over ( partition by source_media_id order by l.link_count desc, rlc.inlink_count desc ) source_rank
        from snapshot_medium_links l
            join top_media slc on ( l.source_media_id = slc.media_id )
            join top_media rlc on ( l.ref_media_id = rlc.media_id )
)

select * from ranked_media where source_rank <= \$2
END

    my $media_map = {};
    map { $media_map->{ $_->{ media_id } } = 1 } @{ $media };

    my $edges = [];
    my $k     = 0;
    for my $media_link ( @{ $media_links } )
    {
        next unless ( $media_map->{ $media_link->{ source_media_id } } && $media_map->{ $media_link->{ ref_media_id } } );
        my $edge = {
            id     => $k++,
            source => $media_link->{ source_media_id },
            target => $media_link->{ ref_media_id },
            weight => ( $include_weights ? $media_link->{ link_count } : 1 )
        };

        push( @{ $edges }, $edge );
    }

    $edges = trim_to_giant_component( $edges );

    return $edges;
}

# given an rgb hex string, return a hash in the form { r => 12, g => 0, b => 255 }, which is
# what we need for the viz:color element of the gexf snapshot
sub get_color_hash_from_hex
{
    my ( $rgb_hex ) = @_;

    return {
        r => hex( substr( $rgb_hex, 0, 2 ) ),
        g => hex( substr( $rgb_hex, 2, 2 ) ),
        b => hex( substr( $rgb_hex, 4, 2 ) )
    };
}

# get a consistent color from MediaWords::Util::Colors.  convert to a color hash as needed by gexf.  translate
# the set to a topic specific color set value for get_consistent_color.
sub get_color
{
    my ( $db, $timespan, $set, $id ) = @_;

    my $color_set;
    if ( grep { $_ eq $set } qw(partisan_code media_type partisan_retweet) )
    {
        $color_set = $set;
    }
    else
    {
        $color_set = "topic_${set}_$timespan->{ snapshot }->{ topics_id }";
    }

    $id ||= 'none';

    my $color = MediaWords::Util::Colors::get_consistent_color( $db, $color_set, $id );

    return get_color_hash_from_hex( $color );
}

# gephi removes the weights from the media links.  add them back in.
sub add_weights_to_gexf_edges
{
    my ( $db, $gexf ) = @_;

    my $edges = $gexf->{ graph }->[ 0 ]->{ edges }->[ 0 ]->{ edge };

    my $medium_links = $db->query( "select * from snapshot_medium_links" )->hashes;

    my $edge_weight_lookup = {};
    for my $m ( @{ $medium_links } )
    {
        $edge_weight_lookup->{ $m->{ source_media_id } }->{ $m->{ ref_media_id } } = $m->{ link_count };
    }

    for my $edge ( @{ $edges } )
    {
        $edge->{ weight } = $edge_weight_lookup->{ $edge->{ source } }->{ $edge->{ target } };
    }
}

# scale the size of the map described in the gexf file to $MAX_MAP_WIDTH and center on 0,0.
# gephi can return really large maps that make the absolute node size relatively tiny.
# we need to scale the map to get consistent, reasonable node sizes across all maps
sub scale_gexf_nodes
{
    my ( $gexf ) = @_;

    my $nodes = $gexf->{ graph }->[ 0 ]->{ nodes }->{ node };

    # my $nodes = $gexf->{ graph }->[ 0 ]->{ nodes }->[ 0 ]->{ node };

    my @undefined_c = grep { !defined( $_->{ 'viz:position' }->{ x } ) } @{ $nodes };

    for my $c ( qw(x y) )
    {
        my @defined_c = grep { defined( $_->{ 'viz:position' }->{ $c } ) } @{ $nodes };
        my $max = List::Util::max( map { $_->{ 'viz:position' }->{ $c } } @defined_c );
        my $min = List::Util::min( map { $_->{ 'viz:position' }->{ $c } } @defined_c );

        my $adjust = 0 - $min - ( $max - $min ) / 2;

        map { $_->{ 'viz:position' }->{ $c } += $adjust } @{ $nodes };

        my $map_width = $max - $min;
        $map_width ||= 1;

        my $scale = $MAX_MAP_WIDTH / $map_width;
        map { $_->{ 'viz:position' }->{ $c } *= $scale } @{ $nodes };
    }
}

# scale the nodes such that the biggest node size is $MAX_NODE_SIZE and the smallest is $MIN_NODE_SIZE
sub scale_node_sizes
{
    my ( $nodes ) = @_;

    map { $_->{ 'viz:size' }->{ value } += 1 } @{ $nodes };

    my $max_size = 1;
    for my $node ( @{ $nodes } )
    {
        my $s = $node->{ 'viz:size' }->{ value };
        $max_size = $s if ( $max_size < $s );
    }

    my $scale = $MAX_NODE_SIZE / $max_size;

    # my $scale = ( $max_size > ( $MAX_NODE_SIZE / $MIN_NODE_SIZE ) ) ? ( $MAX_NODE_SIZE / $max_size ) : 1;

    for my $node ( @{ $nodes } )
    {
        my $s = $node->{ 'viz:size' }->{ value };

        $s = int( $scale * $s );

        $s = $MIN_NODE_SIZE if ( $s < $MIN_NODE_SIZE );

        $node->{ 'viz:size' }->{ value } = $s;
    }
}

# remove edges going into the top $num nodes.  return the pruned edges.
sub prune_links_to_top_nodes
{
    my ( $nodes, $edges, $num ) = @_;

    return $edges unless ( @{ $nodes } && @{ $edges } && ( $num > 0 ) );

    my $prune_lookup = {};
    map { $prune_lookup->{ $_->{ id } } = 1 } @{ $nodes }[ 0 .. $num - 1 ];

    my $pruned_edges = [];
    for my $edge ( @{ $edges } )
    {
        push( @{ $pruned_edges }, $edge ) unless ( $prune_lookup->{ $edge->{ target } } );
    }

    DEBUG "pruned edges: " . ( scalar( @{ $edges } ) - scalar( @{ $pruned_edges } ) );

    return $pruned_edges;
}

# remove all edges to any node with a size greater than the min size
sub prune_links_to_min_size
{
    my ( $nodes, $edges ) = @_;

    my $min_size = List::Util::min( map { $_->{ 'viz:size' }->{ value } } @{ $nodes } );

    my $min_size_nodes = {};
    map { $min_size_nodes->{ $_->{ id } } = 1 if ( $_->{ 'viz:size' }->{ value } <= $min_size ) } @{ $nodes };

    my $pruned_edges = [];
    for my $edge ( @{ $edges } )
    {
        push( @{ $pruned_edges }, $edge ) if ( $min_size_nodes->{ $edge->{ target } } );
    }

    DEBUG "pruned edges: " . ( scalar( @{ $edges } ) - scalar( @{ $pruned_edges } ) );

    return $pruned_edges;
}

# call mediawords.tm.snapshot.graph_layout.layout_gexf
sub layout_gexf($)
{
    my ( $gexf ) = @_;

    my $nodes = $gexf->{ graph }->[ 0 ]->{ nodes }->{ node };

    my $layout;

    if ( scalar( @{ $nodes } ) < $MAX_LAYOUT_SOURCES )
    {
        DEBUG( "laying out grap with " . scalar( @{ $nodes } ) . " sources ..." );
        my $xml = XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );

        $layout = MediaWords::TM::Snapshot::GraphLayout::layout_gexf( $xml );
    }
    else
    {
        WARN( "refusing to layout graph with more than $MAX_LAYOUT_SOURCES sources" );
        $layout = {};
    }

    for my $node ( @{ $nodes } )
    {
        my $pos = $layout->{ $node->{ id } };
        my ( $x, $y ) = $pos ? @{ $pos } : ( 0, 0 );
        $node->{ 'viz:position' }->{ x } = $x;
        $node->{ 'viz:position' }->{ y } = $y;
    }

    # scale_gexf_nodes( $gexf );
}

# get a descirption for the gexf file export
sub _get_gexf_description($$)
{
    my ( $db, $timespan ) = @_;

    my $topic = $db->query( <<SQL, $timespan->{ snapshots_id } )->hash;
select * from topics t join snapshots s using ( topics_id ) where snapshots_id = ?
SQL

    my $description = <<END;
Media Cloud topic map of $topic->{ name } for $timespan->{ period } timespan
from $timespan->{ start_date } to $timespan->{ end_date }
END

    if ( $timespan->{ foci_id } )
    {
        my $focus = $db->require_by_id( 'foci', $timespan->{ foci_id } );
        $description .= "for $focus->{ name } focus";
    }

    return $description;
}

=head2 get_gexf_snapshot( $db, $timespan, $options )

Get a gexf snapshot of the graph described by the linked media sources within the given topic timespan.

Layout the graph using the gaphviz neato algorithm.

Accepts these $options:

* color_field - color the nodes by the given field: $medium->{ $color_field } (default 'media_type').
* max_media -  include only the $max_media media sources with the most inlinks in the timespan (default 500).
* include_weights - if true, use weighted edges
* max_links_per_medium - if set, only inclue the top $max_links_per_media out links from each medium, sorted by medium_link_counts.link_count and then inlink_count of the target medium
* exclude_media_ids - list of media_ids to exclude

=cut

sub get_gexf_snapshot
{
    my ( $db, $timespan, $options ) = @_;

    $options->{ max_media }   ||= $MAX_GEXF_MEDIA;
    $options->{ color_field } ||= 'media_type';

    my $exclude_media_ids_list = join( ',', map { int( $_ ) } ( @{ $options->{ exclude_media_ids } }, 0 ) );

    my $media = $db->query( <<END, $options->{ max_media } )->hashes;
select distinct
        m.*,
        mlc.media_inlink_count inlink_count,
        mlc.story_count,
        mlc.facebook_share_count,
        mlc.simple_tweet_count,
        mlc.normalized_tweet_count
    from snapshot_media_with_types m
        join snapshot_medium_link_counts mlc using ( media_id )
    where
        m.media_id not in ( $exclude_media_ids_list )
    order
        by mlc.media_inlink_count desc
    limit ?
END

    add_extra_fields_to_snapshot_media( $db, $timespan, $media );

    my $gexf = {
        'xmlns'              => "http://www.gexf.net/1.2draft",
        'xmlns:xsi'          => "http://www.w3.org/2001/XMLSchema-instance",
        'xmlns:viz'          => "http://www.gexf.net/1.1draft/viz",
        'xsi:schemaLocation' => "http://www.gexf.net/1.2draft http://www.gexf.net/1.2draft/gexf.xsd",
        'version'            => "1.2",
    };

    my $meta = { 'lastmodifieddate' => Date::Format::time2str( '%Y-%m-%d', time ) };
    push( @{ $gexf->{ meta } }, $meta );

    push( @{ $meta->{ creator } }, 'Berkman Center' );

    my $description = _get_gexf_description( $db, $timespan );
    push( @{ $meta->{ description } }, $description );

    my $graph = {
        'mode'            => "static",
        'defaultedgetype' => "directed",
    };
    push( @{ $gexf->{ graph } }, $graph );

    my $attributes = { class => 'node', mode => 'static' };
    push( @{ $graph->{ attributes } }, $attributes );

    my $i = 0;
    while ( my ( $name, $type ) = each( %{ $_media_static_gexf_attribute_types } ) )
    {
        push( @{ $attributes->{ attribute } }, { id => $i++, title => $name, type => $type } );
    }

    my $edges = get_weighted_edges( $db, $media, $options );
    $graph->{ edges }->{ edge } = $edges;

    my $edge_lookup;
    map { $edge_lookup->{ $_->{ source } } = 1; $edge_lookup->{ $_->{ target } } = 1; } @{ $edges };

    my $total_link_count = 1;
    map { $total_link_count += $_->{ inlink_count } } @{ $media };

    for my $medium ( @{ $media } )
    {
        next unless ( $edge_lookup->{ $medium->{ media_id } } );

        my $node = {
            id    => $medium->{ media_id },
            label => $medium->{ name },
        };

        # FIXME should this be configurable?
        $medium->{ view_medium } = 'https://sources.mediacloud.org/#/sources/' . $medium->{ media_id };

        my $j = 0;
        while ( my ( $name, $type ) = each( %{ $_media_static_gexf_attribute_types } ) )
        {
            my $value = $medium->{ $name };
            if ( !defined( $value ) )
            {
                $value = ( $type eq 'integer' ) ? 0 : '';
            }

            push( @{ $node->{ attvalues }->{ attvalue } }, { for => $j++, value => $value } );
        }

        my $color_field = $options->{ color_field };
        $node->{ 'viz:color' } = [ get_color( $db, $timespan, $color_field, $medium->{ $color_field } ) ];
        $node->{ 'viz:size' } = { value => $medium->{ inlink_count } + 1 };

        push( @{ $graph->{ nodes }->{ node } }, $node );
    }

    scale_node_sizes( $graph->{ nodes }->{ node } );

    layout_gexf( $gexf );

    my $xml = XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );

    return $xml;
}

# return true if there are any stories in the current topic_stories_snapshot_ table
sub stories_exist_for_period
{
    my ( $db, $topic ) = @_;

    return $db->query( "select 1 from snapshot_period_stories" )->hash;
}

sub create_timespan ($$$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period, $focus ) = @_;

    my $timespan = {
        snapshots_id      => $cd->{ snapshots_id },
        start_date        => $start_date,
        end_date          => $end_date,
        period            => $period,
        story_count       => 0,
        story_link_count  => 0,
        medium_count      => 0,
        medium_link_count => 0,
        tweet_count       => 0,
        foci_id           => $focus ? $focus->{ foci_id } : undef
    };

    $timespan = $db->create( 'timespans', $timespan );

    $timespan->{ snapshot } = $cd;

    return $timespan;
}

# generate data for the story_links, story_link_counts, media_links, media_link_counts tables
# based on the data in the temporary snapshot_* tables
sub generate_timespan_data ($$;$)
{
    my ( $db, $timespan, $is_model ) = @_;

    write_period_stories( $db, $timespan );

    write_timespan_tweets_snapshot( $db, $timespan );

    write_story_links_snapshot( $db, $timespan, $is_model );
    write_story_link_counts_snapshot( $db, $timespan, $is_model );
    write_medium_links_snapshot( $db, $timespan, $is_model );
    write_medium_link_counts_snapshot( $db, $timespan, $is_model );

}

# Update story_count, story_link_count, medium_count, and medium_link_count fields in the timespan
# hash.  This must be called after create_temporary_snapshot_views() to get access to these fields in the timespan hash.
#
# Save to db unless $live is specified.
sub __update_timespan_counts($$;$)
{
    my ( $db, $timespan, $live ) = @_;

    ( $timespan->{ story_count } ) = $db->query( "select count(*) from snapshot_story_link_counts" )->flat;

    ( $timespan->{ story_link_count } ) = $db->query( "select count(*) from snapshot_story_links" )->flat;

    ( $timespan->{ medium_count } ) = $db->query( "select count(*) from snapshot_medium_link_counts" )->flat;

    ( $timespan->{ medium_link_count } ) = $db->query( "select count(*) from snapshot_medium_links" )->flat;

    ( $timespan->{ tweet_count } ) = $db->query( "select count(*) from snapshot_timespan_tweets" )->flat;

    return if ( $live );

    for my $field ( qw(story_count story_link_count medium_count medium_link_count) )
    {
        update_timespan( $db, $timespan, $field, $timespan->{ $field } );
    }
}

# generate the snapshot timespans for the given period, dates, and tag
sub generate_timespan ($$$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period, $focus ) = @_;

    my $timespan = create_timespan( $db, $cd, $start_date, $end_date, $period, $focus );

    my $snapshot_label = "${ period }: ${ start_date } - ${ end_date } ";
    $snapshot_label .= "[ $focus->{ name } ]" if ( $focus );

    DEBUG( "generating $snapshot_label ..." );

    MediaWords::Job::TM::SnapshotTopic->update_job_state_message( $db, "snapshotting $snapshot_label" );

    my $all_models_top_media = MediaWords::TM::Model::get_all_models_top_media( $db, $timespan );

    DEBUG( "generating snapshot data ..." );
    generate_timespan_data( $db, $timespan );

    __update_timespan_counts( $db, $timespan );

    $all_models_top_media ||= [ MediaWords::TM::Model::get_top_media_link_counts( $db, $timespan ) ];

    MediaWords::TM::Model::print_model_matches( $db, $timespan, $all_models_top_media );
    MediaWords::TM::Model::update_model_correlation( $db, $timespan, $all_models_top_media );
}

# decrease the given date to the latest monday equal to or before the date
sub truncate_to_monday ($)
{
    my ( $date ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $week_day   = ( localtime( $epoch_date ) )[ 6 ];

    # mod this to account for sunday, for which $week_day - 1 == -1
    my $days_offset = ( $week_day - 1 ) % 7;

    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# decrease the given date to the first day of the current month
sub truncate_to_start_of_month ($)
{
    my ( $date ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $month_day  = ( localtime( $epoch_date ) )[ 3 ];

    my $days_offset = $month_day - 1;

    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# generate snapshots for the periods in topic_dates
sub generate_custom_period_snapshot ($$$ )
{
    my ( $db, $cd, $focus ) = @_;

    my $topic_dates = $db->query( <<END, $cd->{ topics_id } )->hashes;
select * from topic_dates where topics_id = ? order by start_date, end_date
END

    for my $topic_date ( @{ $topic_dates } )
    {
        my $start_date = $topic_date->{ start_date };
        my $end_date   = $topic_date->{ end_date };
        generate_timespan( $db, $cd, $start_date, $end_date, 'custom', $focus );
    }
}

# generate snapshot for the given period (overall, monthly, weekly, or custom) and the given tag
sub generate_period_snapshot ($$$$)
{
    my ( $db, $cd, $period, $focus ) = @_;

    my $start_date = $cd->{ start_date };
    my $end_date   = $cd->{ end_date };

    if ( $period eq 'overall' )
    {
        # this will generate an 'overall' timespan with all stories
        generate_timespan( $db, $cd, $start_date, $end_date, $period, $focus );
    }
    elsif ( $period eq 'weekly' )
    {
        my $w_start_date = truncate_to_monday( $start_date );
        while ( $w_start_date lt $end_date )
        {
            my $w_end_date = MediaWords::Util::SQL::increment_day( $w_start_date, 7 );

            generate_timespan( $db, $cd, $w_start_date, $w_end_date, $period, $focus );

            $w_start_date = $w_end_date;
        }
    }
    elsif ( $period eq 'monthly' )
    {
        my $m_start_date = truncate_to_start_of_month( $start_date );
        while ( $m_start_date lt $end_date )
        {
            my $m_end_date = MediaWords::Util::SQL::increment_day( $m_start_date, 32 );
            $m_end_date = truncate_to_start_of_month( $m_end_date );

            generate_timespan( $db, $cd, $m_start_date, $m_end_date, $period, $focus );

            $m_start_date = $m_end_date;
        }
    }
    elsif ( $period eq 'custom' )
    {
        generate_custom_period_snapshot( $db, $cd, $focus );
    }
    else
    {
        die( "Unknown period '$period'" );
    }
}

# create temporary table copies of temporary tables so that we can copy
# the data back into the main temporary tables after tweaking the main temporary tables
sub copy_temporary_tables
{
    my ( $db ) = @_;

    my $snapshot_tables = __get_snapshot_tables();
    for my $snapshot_table ( @{ $snapshot_tables } )
    {
        my $snapshot_table = "snapshot_${ snapshot_table }";
        my $copy_table     = "_copy_${ snapshot_table }";

        $db->query( "drop table if exists $copy_table" );
        $db->query( "create temporary table $copy_table $_temporary_tablespace as select * from $snapshot_table" );
    }
}

# restore original, copied data back into snapshot tables
sub restore_temporary_tables
{
    my ( $db ) = @_;

    my $snapshot_tables = __get_snapshot_tables();
    for my $snapshot_table ( @{ $snapshot_tables } )
    {
        my $snapshot_table = "snapshot_${ snapshot_table }";
        my $copy_table     = "_copy_${ snapshot_table }";

        $db->query( "drop table if exists $snapshot_table cascade" );
        $db->query( "create temporary table $snapshot_table $_temporary_tablespace as select * from $copy_table" );
    }

    add_media_type_views( $db );
}

# create a snapshot for the given table from the temporary snapshot_* table,
# making sure to specify all the fields in the copy so that we don't have to
# assume column position is the same in the original and snapshot tables.
# use the $key from $obj as an additional field in the snapshot table.
sub create_snapshot
{
    my ( $db, $obj, $key, $table ) = @_;

    DEBUG( "snapshot $table..." );

    my $column_names = [ $db->query( <<END, $table, $key )->flat ];
select column_name from information_schema.columns
    where table_name = ? and table_schema = 'snap' and
        column_name not in ( ? )
    order by ordinal_position asc
END

    die( "Field names can only have letters and underscores" ) if ( grep { /[^a-z_]/i } @{ $column_names } );
    die( "Table name can only have letters and underscores" ) if ( $table =~ /[^a-z_]/i );

    my $column_list = join( ",", @{ $column_names } );

    $db->query( <<END, $obj->{ $key } );
insert into snap.${ table } ( $column_list, $key ) select $column_list, ? from snapshot_${ table }
END

}

# create a snapshot of a table for a timespan
sub create_timespan_snapshot
{
    my ( $db, $timespan, $table ) = @_;

    create_snapshot( $db, $timespan, 'timespans_id', $table );
}

# create a snapshot of a table for a snapshot
sub create_snap_snapshot
{
    my ( $db, $cd, $table ) = @_;

    create_snapshot( $db, $cd, 'snapshots_id', $table );
}

# generate temporary snapshot_* tables for the specified snapshot for each of the snapshot_tables.
# these are the tables that apply to the whole snapshot.
sub write_temporary_snapshot_tables($$$)
{
    my ( $db, $topic, $snapshot ) = @_;

    my $topics_id = $topic->{ topics_id };

    set_temporary_table_tablespace();

    $db->query( <<END, $topics_id );
create temporary table snapshot_topic_stories $_temporary_tablespace as
    select cs.*
        from topic_stories cs
        where cs.topics_id = ?
END

    $db->query( <<END, $topics_id );
create temporary table snapshot_topic_media_codes $_temporary_tablespace as
    select cmc.*
        from topic_media_codes cmc
        where cmc.topics_id = ?
END

    $db->query( <<END, $topics_id );
create temporary table snapshot_stories $_temporary_tablespace as
    select s.stories_id, s.media_id, s.url, s.guid, s.title, s.publish_date, s.collect_date, s.full_text_rss, s.language
        from snap.live_stories s
            join snapshot_topic_stories dcs on ( s.stories_id = dcs.stories_id and s.topics_id = ? )
END

    $db->query( <<END );
create temporary table snapshot_media $_temporary_tablespace as
    select m.* from media m
        where m.media_id in ( select media_id from snapshot_stories )
END

    $db->query( <<END, $topics_id );
create temporary table snapshot_topic_links_cross_media $_temporary_tablespace as
    select s.stories_id, r.stories_id ref_stories_id, cl.url, cs.topics_id, cl.topic_links_id
        from topic_links cl
            join snapshot_topic_stories cs on ( cs.stories_id = cl.ref_stories_id )
            join snapshot_stories s on ( cl.stories_id = s.stories_id )
            join snapshot_media sm on ( s.media_id = sm.media_id )
            join snapshot_stories r on ( cl.ref_stories_id = r.stories_id )
            join snapshot_media rm on ( r.media_id= rm.media_id )
        where cl.topics_id = ? and r.media_id <> s.media_id
END

    $db->query( <<END );
create temporary table snapshot_stories_tags_map $_temporary_tablespace as
    select stm.*
    from stories_tags_map stm, snapshot_stories ds
    where stm.stories_id = ds.stories_id
END

    $db->query( <<END );
create temporary table snapshot_media_tags_map $_temporary_tablespace as
    select mtm.*
    from media_tags_map mtm, snapshot_media dm
    where mtm.media_id = dm.media_id
END

    $db->query( <<END );
create temporary table snapshot_tags $_temporary_tablespace as
    select distinct t.* from tags t where t.tags_id in
        ( select a.tags_id
            from tags a
                join snapshot_media_tags_map amtm on ( a.tags_id = amtm.tags_id )

          union

          select b.tags_id
            from tags b
                join snapshot_stories_tags_map bstm on ( b.tags_id = bstm.tags_id )
        )

END

    $db->query( <<END );
create temporary table snapshot_tag_sets $_temporary_tablespace as
    select ts.*
        from tag_sets ts
        where ts.tag_sets_id in ( select tag_sets_id from snapshot_tags )
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

    $db->query( <<SQL, $tweet_topics_id );
create temporary table snapshot_tweet_stories as
    with tweets_per_day as (
        select topic_tweets_id,
                ( tt.data->'tweet'->'user'->>'statuses_count' ) ::int tweets,
                extract( day from now() - ( tt.data->'tweet'->'user'->>'created_at' )::date ) days
            from topic_tweets tt
                join topic_tweet_days ttd using ( topic_tweet_days_id )
            where ttd.topics_id = \$1
    )

    select topic_tweets_id, u.publish_date, twitter_user, stories_id, media_id, num_ch_tweets, tweet_count
        from topic_tweet_full_urls u
            join tweets_per_day tpd using ( topic_tweets_id )
            join snapshot_stories using ( stories_id )
        where
            topics_id = \$1 $bot_clause
SQL

    add_media_type_views( $db );

    for my $table ( @{ __get_snapshot_tables() } )
    {
        my $table_exists = $db->query( "select * from pg_class where relname = ?", $table )->hash;
        die( "snapshot not created for snapshot table: $table" ) unless ( $table_exists );
    }

}

sub add_media_type_views
{
    my ( $db ) = @_;

    $db->query( <<END );
create or replace view snapshot_media_with_types as
    with topics_id as (
        select topics_id from snapshot_topic_stories limit 1
    )

    select
            m.*,
            case
                when ( ct.label <> 'Not Typed' )
                    then ct.label
                when ( ut.label is not null )
                    then ut.label
                else
                    'Not Typed'
                end as media_type
        from
            snapshot_media m
            left join (
                snapshot_tags ut
                join snapshot_tag_sets uts on ( ut.tag_sets_id = uts.tag_sets_id and uts.name = 'media_type' )
                join snapshot_media_tags_map umtm on ( umtm.tags_id = ut.tags_id )
            ) on ( m.media_id = umtm.media_id )
            left join (
                snapshot_tags ct
                join snapshot_media_tags_map cmtm on ( cmtm.tags_id = ct.tags_id )
                join topics c on ( c.media_type_tag_sets_id = ct.tag_sets_id )
                join topics_id cid on ( c.topics_id = cid.topics_id )
            ) on ( m.media_id = cmtm.media_id )
END

    $db->query( <<END );
create or replace view snapshot_stories_with_types as
    select s.*, m.media_type
        from snapshot_stories s join snapshot_media_with_types m on ( s.media_id = m.media_id )
END

}

# generate snapshots for all of the __get_snapshot_tables() from the temporary snapshot tables
sub generate_snapshots_from_temporary_snapshot_tables
{
    my ( $db, $cd ) = @_;

    my $snapshot_tables = __get_snapshot_tables();

    map { create_snap_snapshot( $db, $cd, $_ ) } @{ $_snapshot_tables };
}

# create the snapshot row for the current snapshot
sub create_snapshot_row ($$$$;$$)
{
    my ( $db, $topic, $start_date, $end_date, $note, $bot_policy ) = @_;

    $note //= '';

    my $cd = $db->query( <<END, $topic->{ topics_id }, $start_date, $end_date, $note, $bot_policy )->hash;
insert into snapshots
    ( topics_id, start_date, end_date, snapshot_date, note, bot_policy )
    values ( ?, ?, ?, now(), ?, ?)
    returning *
END

    $cd->{ topic } = $topic;

    return $cd;
}

# analyze all of the snapshot tables because otherwise immediate queries to the
# new snapshot ids offer trigger seq scans
sub analyze_snapshot_tables
{
    my ( $db ) = @_;

    DEBUG( "analyzing tables..." );

    my $snapshot_tables = __get_snapshot_tables();

    for my $t ( @{ $snapshot_tables } )
    {
        $db->query( "analyze snap.$t" );
    }
}

# validate and set the periods for the snapshot based on the period parameter
sub get_periods ($)
{
    my ( $period ) = @_;

    $period ||= 'all';

    my $all_periods = [ qw(custom overall weekly monthly) ];

    die( "period must be all, custom, overall, weekly, or monthly" )
      if ( $period && !grep { $_ eq $period } ( 'all', @{ $all_periods } ) );

    return ( $period eq 'all' ) ? $all_periods : [ $period ];
}

# generate period spanshots for each period / focus / timespan combination
sub generate_period_focus_snapshots ( $$$ )
{
    my ( $db, $snapshot, $periods ) = @_;

    my $fsds = $db->query( <<SQL, $snapshot->{ topics_id } )->hashes;
select * from focal_set_definitions where topics_id = ? and focal_technique = 'Boolean Query'
SQL

    for my $fsd ( @{ $fsds } )
    {
        my $focal_set = $db->query( <<SQL, $fsd->{ focal_set_definitions_id }, $snapshot->{ snapshots_id } )->hash;
insert into focal_sets ( name, description, focal_technique, snapshots_id )
    select name, description, focal_technique, \$2 from focal_set_definitions where focal_set_definitions_id = \$1
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
    returning *
SQL
            map { generate_period_snapshot( $db, $snapshot, $_, $focus ) } @{ $periods };
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
        die( "uknown period: '$period'" ) unless ( grep { $period eq $_ } @{ $allowed_periods } );
    }
}

=head2 snapshot_topic( $db, $topics_id, $note, $bot_policy, $periods )

Create a snapshot for the given topic.  Optionally pass a note and/or a bot_policy field to the created snapshot.

The bot_policy should be one of 'all', 'no bots', or 'only bots' indicating for twitter topics whether and how to
filter for bots (a bot is defined as any user tweeting more than 200 post per day).

The periods should be a list of periods to include in the snapshot, where the allowed periods are custom,
overall, weekly, and monthly.  If periods is not specificied or is empty, all periods will be generated.

Returns snapshot ID of a newly generated snapshot.

=cut

sub snapshot_topic ($$;$$$)
{
    my ( $db, $topics_id, $note, $bot_policy, $periods ) = @_;

    my $allowed_periods = [ qw(custom overall weekly monthly) ];

    $periods = $allowed_periods if ( !$periods || !@{ $periods } );

    _validate_periods( $periods, $allowed_periods );

    my $topic = $db->find_by_id( 'topics', $topics_id )
      || die( "Unable to find topic '$topics_id'" );

    $db->set_print_warn( 0 );    # avoid noisy, extraneous postgres notices from drops

    # Log activity that's about to start
    my $changes = {};
    unless ( MediaWords::DBI::Activities::log_system_activity( $db, 'tm_snapshot_topic', $topics_id + 0, $changes ) )
    {
        die "Unable to log the 'tm_snapshot_topic' activity.";
    }

    my ( $start_date, $end_date ) = ( $topic->{ start_date }, $topic->{ end_date } );

    my $snap = create_snapshot_row( $db, $topic, $start_date, $end_date, $note, $bot_policy );

    MediaWords::Job::TM::SnapshotTopic->update_job_state_args( $db, { snapshots_id => $snap->{ snapshots_id } } );
    MediaWords::Job::TM::SnapshotTopic->update_job_state_message( $db, "snapshotting data" );

    write_temporary_snapshot_tables( $db, $topic, $snap );

    generate_snapshots_from_temporary_snapshot_tables( $db, $snap );

    # generate null focus timespan snapshots
    map { generate_period_snapshot( $db, $snap, $_, undef ) } ( @{ $periods } );

    generate_period_focus_snapshots( $db, $snap, $periods );

    MediaWords::Job::TM::SnapshotTopic->update_job_state_message( $db, "finalizing snapshot" );

    _export_stories_to_solr( $db, $snap );

    analyze_snapshot_tables( $db );

    discard_temp_tables( $db );

    # update this manually because snapshot_topic might be called directly from Mine::mine_topic()
    $db->update_by_id( 'snapshots', $snap->{ snapshots_id }, { state => $MediaWords::AbstractJob::STATE_COMPLETED } );
    MediaWords::TM::send_topic_alert( $db, $topic, "new topic snapshot is ready" );

    return $snap->{ snapshots_id };
}

1;
