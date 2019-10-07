package MediaWords::TM::Mine;

=head1 NAME

MediaWords::TM::Mine - topic spider implementation

=head1 SYNOPSIS

    MediaWords::TM::Mine::mine_topic( $db, $options );

=head1 DESCRIPTION

The topic mining process is described in doc/topic_mining.markdown.

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use List::Util;
use Readonly;

use MediaWords::TM::Alert;
use MediaWords::TM::FetchTopicPosts;
use MediaWords::TM::Stories;
use MediaWords::DBI::Stories::GuessDate;
use MediaWords::JobManager::Job;
use MediaWords::JobManager::StatefulJob;
use MediaWords::Solr;
use MediaWords::Solr::Query;
use MediaWords::Util::SQL;
use MediaWords::JobManager::AbstractStatefulJob;

# total time to wait for fetching of social media metrics
Readonly my $MAX_SOCIAL_MEDIA_FETCH_TIME => ( 60 * 60 * 24 );

# add new links in chunks of this size
Readonly my $ADD_NEW_LINKS_CHUNK_SIZE => 10_000;

# extract story links in chunks of this size
Readonly my $EXTRACT_STORY_LINKS_CHUNK_SIZE => 1000;

# query this many topic_links at a time to spider
Readonly my $SPIDER_LINKS_CHUNK_SIZE => 100_000;

# die if the error rate for link fetch or link extract jobs is greater than this
Readonly my $MAX_JOB_ERROR_RATE => 0.02;

# timeout when polling for jobs to finish
Readonly my $JOB_POLL_TIMEOUT => 3600;

# number of seconds to wait when polling for jobs to finish
Readonly my $JOB_POLL_WAIT => 5;

# if more than this many seed urls are imported, dedup stories before as well as after spidering
Readonly my $MIN_SEED_IMPORT_FOR_PREDUP_STORIES => 50_000;

# if mine_topic is run with the test_mode option, set this true and do not try to queue extractions
my $_test_mode;

# update topics.state in the database
sub update_topic_state($$$;$)
{
    my ( $db, $topic, $message ) = @_;

    INFO( "update topic state: $message" );

    eval { MediaWords::JobManager::AbstractStatefulJob::update_job_state_message( $db, 'MediaWords::Job::TM::MineTopic', $message ) };
    if ( $@ )
    {
        die "error updating job state: $@";
    }
}

# return true if the publish date of the story is within 7 days of the topic date range or if the
# story is undateable
sub story_within_topic_date_range
{
    my ( $db, $topic, $story ) = @_;

    my $story_date = substr( $story->{ publish_date }, 0, 10 );

    my $start_date = $topic->{ start_date };
    $start_date = MediaWords::Util::SQL::increment_day( $start_date, -7 );
    $start_date = substr( $start_date, 0, 10 );

    my $end_date = $topic->{ end_date };
    $end_date = MediaWords::Util::SQL::increment_day( $end_date, 7 );
    $end_date = substr( $end_date, 0, 10 );

    return 1 if ( ( $story_date ge $start_date ) && ( $story_date le $end_date ) );

    return MediaWords::DBI::Stories::GuessDate::is_undateable( $db, $story );
}

# submit jobs to extract links from the given stories and then poll to wait for the stories to be processed within
# the jobs pool
sub generate_topic_links
{
    my ( $db, $topic, $stories ) = @_;

    INFO "generate topic links: " . scalar( @{ $stories } );

    my $topic_links = [];

    if ( $topic->{ platform } ne 'web' )
    {
        INFO( "skip link generation for non web topic" );
        return;
    }

    my $stories_ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    $db->query( <<SQL, $topic->{ topics_id } );
update topic_stories set link_mined = 'f'
        where
            stories_id in ( select id from $stories_ids_table ) and
            topics_id = ? and
            link_mined = 't'
SQL

    my $queued_stories_ids = [];
    for my $story ( @{ $stories } )
    {
        next unless ( story_within_topic_date_range( $db, $topic, $story ) );

        push( @{ $queued_stories_ids }, $story->{ stories_id } );

        MediaWords::JobManager::Job::add_to_queue(
            'MediaWords::Job::TM::ExtractStoryLinks',                                       #
            { stories_id => $story->{ stories_id }, topics_id => $topic->{ topics_id } },   #
        );

        TRACE( "queued link extraction for story $story->{ title } $story->{ url }." );
    }

    INFO( "waiting for " . scalar( @{ $queued_stories_ids } ) . " link extraction jobs to finish" );

    my $queued_ids_table = $db->get_temporary_ids_table( $queued_stories_ids );

    # poll every $sleep_time seconds waiting for the jobs to complete.  die if the number of stories left to process
    # has not shrunk for $large_timeout seconds.  warn but continue if the number of stories left to process
    # is only 5% of the total and short_timeout has passed (this is to make the topic not hang entirely because
    # of one link extractor job error).
    my $prev_num_queued_stories = scalar( @{ $stories } );
    my $last_change_time        = time();
    while ( 1 )
    {
        my ( $num_queued_stories ) = $db->query( <<SQL, $topic->{ topics_id } )->flat();
select count(*)
    from topic_stories
    where
        stories_id in ( select id from $queued_ids_table ) and
        topics_id = ? and
        link_mined = 'f'
SQL

        last if ( $num_queued_stories == 0 );

        $last_change_time = time() if ( $num_queued_stories != $prev_num_queued_stories );
        if ( ( time() - $last_change_time ) > $JOB_POLL_TIMEOUT )
        {
            my $queued_ids = $db->query( "select * from $queued_ids_table limit 5" )->flat();
            my $ids_list = join( ', ', @{ $queued_ids } );
            LOGDIE( "Timed out waiting for story link extraction ($ids_list)." );
        }

        INFO( "$num_queued_stories stories left in link extraction pool...." );

        $prev_num_queued_stories = $num_queued_stories;
        sleep( $JOB_POLL_WAIT );
    }

    $db->query( <<SQL, $topic->{ topics_id } );
update topic_stories set link_mined = 't'
    where
        stories_id in ( select id from $stories_ids_table ) and
        topics_id = ? and
        link_mined = 'f'
SQL

    $db->query( "discard temp" );
}

# die() with an appropriate error if topic_stories > topics.max_stories; because this check is expensive and we don't
# care if the topic goes over by a few thousand stories, we only actually run the check randmly 1/1000 of the time
sub die_if_max_stories_exceeded($$)
{
    my ( $db, $topic ) = @_;

    my ( $num_topic_stories ) = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select count(*) from topic_stories where topics_id = ?
SQL

    if ( $num_topic_stories > $topic->{ max_stories } )
    {
        LOGDIE( "topic has $num_topic_stories stories, which exceeds topic max stories of $topic->{ max_stories }" );
    }
}

# add the topic_fetch_url to the fetch_link job queue.  try repeatedly on failure.
sub queue_topic_fetch_url($;$)
{
    my ( $tfu, $domain_timeout ) = @_;

    $domain_timeout //= $_test_mode ? 0 : undef;

    MediaWords::JobManager::Job::add_to_queue(
        'MediaWords::Job::TM::FetchLink',
        {
            topic_fetch_urls_id => $tfu->{ topic_fetch_urls_id },
            domain_timeout      => $domain_timeout
        }
    );
}

# create topic_fetch_urls rows correpsonding to the links and queue a FetchLink job for each.  return the tfu rows.
sub create_and_queue_topic_fetch_urls($$$)
{
    my ( $db, $topic, $fetch_links ) = @_;

    my $tfus = [];
    for my $link ( @{ $fetch_links } )
    {
        my $tfu = $db->create(
            'topic_fetch_urls',
            {
                topics_id      => $topic->{ topics_id },
                url            => $link->{ url },
                state          => 'pending',
                assume_match   => MediaWords::Util::Python::normalize_boolean_for_db( $link->{ assume_match } ),
                topic_links_id => $link->{ topic_links_id },
            }
        );
        push( @{ $tfus }, $tfu );

        queue_topic_fetch_url( $tfu );
    }

    return $tfus;
}

sub _fetch_twitter_urls($$$)
{
    my ( $db, $topic, $tfu_ids_table ) = @_;

    my $twitter_tfu_ids = $db->query( <<SQL )->flat();
select topic_fetch_urls_id
    from topic_fetch_urls tfu
        join $tfu_ids_table ids on ( tfu.topic_fetch_urls_id = ids.id )
    where
        tfu.state = 'tweet pending'
SQL

    return unless ( scalar( @{ $twitter_tfu_ids } ) > 0 );

    $tfu_ids_table = $db->get_temporary_ids_table( $twitter_tfu_ids );

    MediaWords::JobManager::Job::add_to_queue( 'MediaWords::Job::TM::FetchTwitterUrls', { topic_fetch_urls_ids => $twitter_tfu_ids } );

    INFO( "waiting for fetch twitter urls job for " . scalar( @{ $twitter_tfu_ids } ) . " urls" );

    # poll every $sleep_time seconds waiting for the jobs to complete.  die if the number of stories left to process
    # has not shrunk for $large_timeout seconds.  warn but continue if the number of stories left to process
    # is only 5% of the total and short_timeout has passed (this is to make the topic not hang entirely because
    # of one link extractor job error).
    my $prev_num_queued_urls = scalar( @{ $twitter_tfu_ids } );
    my $last_change_time     = time();
    while ( 1 )
    {
        my $queued_tfus = $db->query( <<SQL )->hashes();
select tfu.*
    from topic_fetch_urls tfu
        join $tfu_ids_table ids on ( tfu.topic_fetch_urls_id = ids.id )
    where
        state in ('tweet pending')
SQL

        my $num_queued_urls = scalar( @{ $queued_tfus } );

        last if ( $num_queued_urls == 0 );

        $last_change_time = time() if ( $num_queued_urls != $prev_num_queued_urls );
        if ( ( time() - $last_change_time ) > $JOB_POLL_TIMEOUT )
        {
            LOGDIE( "Timed out waiting for twitter fetching.\n" . Dumper( $queued_tfus ) );
        }

        INFO( "$num_queued_urls twitter urls left to fetch ..." );

        $prev_num_queued_urls = $num_queued_urls;
        sleep( $JOB_POLL_WAIT );
    }
}

# fetch the given links by creating topic_fetch_urls rows and sending them to the FetchLink queue
# for processing.  wait for the queue to complete and returnt the resulting topic_fetch_urls.
sub fetch_links
{
    my ( $db, $topic, $fetch_links ) = @_;

    INFO( "fetch_links: queue links" );
    my $tfus = create_and_queue_topic_fetch_urls( $db, $topic, $fetch_links );
    my $num_queued_links = scalar( @{ $fetch_links } );

    INFO( "waiting for fetch link queue: $num_queued_links queued" );

    my $tfu_ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ topic_fetch_urls_id } ) } @{ $tfus } ] );

    my $requeues         = 0;
    my $max_requeues     = 10;
    my $max_requeue_jobs = 100;
    my $requeue_timeout  = 30;
    my $instant_requeued = 0;

    # once the pool is this small, just requeue everything with a 0 per site throttle
    my $instant_queue_size = 25;

    # how many times to requeues everything if there is no change for $JOB_POLL_TIMEOUT seconds
    my $full_requeues     = 0;
    my $max_full_requeues = 2;

    my $last_pending_change   = time();
    my $last_num_pending_urls = 0;
    while ( 1 )
    {
        my $pending_urls = $db->query( <<SQL )->hashes();
select *, coalesce( fetch_date::text, 'null' ) fetch_date
    from topic_fetch_urls
    where
        topic_fetch_urls_id in ( select id from $tfu_ids_table ) and
        state in ( 'pending', 'requeued' )
SQL

        my $pending_url_ids = [ map { $_->{ topic_fetch_urls_id } } @{ $pending_urls } ];

        my $num_pending_urls = scalar( @{ $pending_url_ids } );

        INFO( "waiting for fetch link queue: $num_pending_urls links remaining ..." );

        # useful in debugging for showing lingering urls
        if ( ( $num_pending_urls <= 5 ) && ( $last_num_pending_urls != $num_pending_urls ) )
        {
            map { INFO( "pending url: $_->{ url } [$_->{ state }: $_->{ fetch_date }]" ) } @{ $pending_urls };
        }

        last if ( $num_pending_urls < 1 );

        # if we only have a handful of job left, requeue them all once with a 0 domain throttle
        if ( !$instant_requeued && ( $num_pending_urls <= $instant_queue_size ) )
        {
            $instant_requeued = 1;
            map { queue_topic_fetch_url( $db->require_by_id( 'topic_fetch_urls', $_ ), 0 ) } @{ $pending_url_ids };
            sleep( $JOB_POLL_WAIT );
            next;
        }

        my $time_since_change = time() - $last_pending_change;

        # for some reason, the fetch_link queue is occasionally losing a small number of jobs.
        if (   ( $time_since_change > $requeue_timeout )
            && ( $requeues < $max_requeues )
            && ( $num_pending_urls < $max_requeue_jobs ) )
        {
            INFO( "requeueing fetch_link $num_pending_urls jobs ... [requeue $requeues]" );

            # requeue with a domain_timeout of 0 so that requeued urls can ignore throttling
            map { queue_topic_fetch_url( $db->require_by_id( 'topic_fetch_urls', $_ ), 0 ) } @{ $pending_url_ids };
            ++$requeues;
            $last_pending_change = time();
        }

        if ( $time_since_change > $JOB_POLL_TIMEOUT )
        {
            if ( $full_requeues < $max_full_requeues )
            {
                map { queue_topic_fetch_url( $db->require_by_id( 'topic_fetch_urls', $_ ) ) } @{ $pending_url_ids };
                ++$full_requeues;
                $last_pending_change = time();
            }
            else
            {
                splice( @{ $pending_url_ids }, 10 );
                my $ids_list = join( ', ', @{ $pending_url_ids } );
                die( "Timed out waiting for fetch_link queue ($ids_list)" );
            }
        }

        $last_pending_change = time() if ( $num_pending_urls < $last_num_pending_urls );

        $last_num_pending_urls = $num_pending_urls;

        sleep( $JOB_POLL_WAIT );
    }

    _fetch_twitter_urls( $db, $topic, $tfu_ids_table );

    INFO( "fetch_links: update topic seed urls" );
    $db->query( <<SQL );
update topic_seed_urls tsu
    set stories_id = tfu.stories_id, processed = 't'
    from topic_fetch_urls tfu
    where
        tfu.url = tsu.url and
        tfu.stories_id is not null and
        tfu.topic_fetch_urls_id in ( select id from $tfu_ids_table ) and
        tfu.topics_id = tsu.topics_id
SQL

    my $completed_tfus = $db->query( <<SQL )->hashes();
select * from topic_fetch_urls where topic_fetch_urls_id in ( select id from $tfu_ids_table )
SQL

    INFO( "completed fetch link queue" );

    return $completed_tfus;
}

# download any unmatched link in new_links, add it as a story, extract it, add any links to the topic_links list.
# each hash within new_links can either be a topic_links hash or simply a hash with a { url } field.  if
# the link is a topic_links hash, the topic_link will be updated in the database to point ref_stories_id
# to the new link story.  For each link, set the { story } field to the story found or created for the link.
sub add_new_links_chunk($$$$)
{
    my ( $db, $topic, $iteration, $new_links ) = @_;

    die_if_max_stories_exceeded( $db, $topic );

    INFO( "add_new_links_chunk: fetch_links" );
    my $topic_fetch_urls = fetch_links( $db, $topic, $new_links );

    INFO( "add_new_links_chunk: mark topic links spidered" );
    my $link_ids = [ grep { $_ } map { $_->{ topic_links_id } } @{ $new_links } ];
    $db->query( <<SQL, $link_ids );
update topic_links set link_spidered  = 't' where topic_links_id = any( ? )
SQL
}

# save a row in the topic_spider_metrics table to track performance of spider
sub save_metrics($$$$$)
{
    my ( $db, $topic, $iteration, $num_links, $elapsed_time ) = @_;

    my $topic_spider_metric = {
        topics_id       => $topic->{ topics_id },
        iteration       => $iteration,
        links_processed => $num_links,
        elapsed_time    => $elapsed_time
    };

    $db->create( 'topic_spider_metrics', $topic_spider_metric );
}

# call add_new_links in chunks of $ADD_NEW_LINKS_CHUNK_SIZE so we don't lose too much work when we restart the spider
sub add_new_links($$$$)
{
    my ( $db, $topic, $iteration, $new_links ) = @_;

    INFO( "add new links" );

    return unless ( @{ $new_links } );

    # randomly shuffle the links because it is better for downloading (which has per medium throttling) and extraction
    # (which has per medium locking) to distribute urls from the same media source randomly among the list of links. the
    # link mining and solr seeding routines that feed most links to this function tend to naturally group links
    # from the same media source together.
    my $shuffled_links = [ List::Util::shuffle( @{ $new_links } ) ];

    my $spider_progress = get_spider_progress_description( $db, $topic, $iteration, scalar( @{ $shuffled_links } ) );

    my $num_links = scalar( @{ $shuffled_links } );
    for ( my $i = 0 ; $i < $num_links ; $i += $ADD_NEW_LINKS_CHUNK_SIZE )
    {
        my $start_time = time;

        update_topic_state( $db, $topic, "$spider_progress; iteration links: $i / $num_links" );

        my $end = List::Util::min( $i + $ADD_NEW_LINKS_CHUNK_SIZE - 1, $#{ $shuffled_links } );
        add_new_links_chunk( $db, $topic, $iteration, [ @{ $shuffled_links }[ $i .. $end ] ] );

        my $elapsed_time = time - $start_time;
        save_metrics( $db, $topic, $iteration, $end - $i, $elapsed_time );
    }

    mine_topic_stories( $db, $topic );
}

# find any links for the topic of this iteration or less that have not already been spidered and call
# add_new_links on them.
sub spider_new_links
{
    my ( $db, $topic, $iteration ) = @_;

    for ( my $i = 0 ; ; $i++ )
    {
        INFO( "spider new links chunk: $i" );

        my $new_links = $db->query( <<END, $iteration, $topic->{ topics_id }, $SPIDER_LINKS_CHUNK_SIZE )->hashes;
select tl.* from topic_links tl, topic_stories ts
    where
        tl.link_spidered = 'f' and
        tl.stories_id = ts.stories_id and
        ( ts.iteration <= \$1 or ts.iteration = 1000 ) and
        ts.topics_id = \$2 and
        tl.topics_id = \$2

    limit \$3
END

        last unless ( @{ $new_links } );

        add_new_links( $db, $topic, $iteration, $new_links );
    }
}

# get short text description of spidering progress
sub get_spider_progress_description
{
    my ( $db, $topic, $iteration, $total_links ) = @_;

    INFO( "get spider progress description" );

    my $cid = $topic->{ topics_id };

    my ( $total_stories ) = $db->query( <<SQL, $cid )->flat;
select count(*) from topic_stories where topics_id = ?
SQL

    my ( $stories_last_iteration ) = $db->query( <<SQL, $cid, $iteration )->flat;
select count(*) from topic_stories where topics_id = ? and iteration = ? - 1
SQL

    my ( $queued_links ) = $db->query( <<SQL, $cid )->flat;
select count(*) from topic_links where topics_id = ? and link_spidered = 'f'
SQL

    return "spidering iteration: $iteration; stories last iteration / total: " .
      "$stories_last_iteration / $total_stories; links queued: $queued_links; iteration links: $total_links";
}

# run the spider over any new links, for $num_iterations iterations
sub run_spider
{
    my ( $db, $topic ) = @_;

    INFO( "run spider" );

    # before we run the spider over links, we need to make sure links have been generated for all existing stories
    mine_topic_stories( $db, $topic );

    map { spider_new_links( $db, $topic, $topic->{ max_iterations } ) } ( 1 .. $topic->{ max_iterations } );
}

# mine for links any stories in topic_stories for this topic that have not already been mined
sub mine_topic_stories
{
    my ( $db, $topic ) = @_;

    INFO( "mine topic stories" );

    # skip for non-web topic, because the below query grows very large without ever mining links
    if ( $topic->{ platform } ne 'web' )
    {
        INFO( "skip link generation for non-web topic" );
        return;
    }

    # chunk the story extractions so that one big topic does not take over the entire queue
    my $i = 0;
    while ( 1 )
    {
        $i += $EXTRACT_STORY_LINKS_CHUNK_SIZE;
        INFO( "mine topic stories: chunked $i ..." );
        my $stories = $db->query( <<SQL, $topic->{ topics_id }, $EXTRACT_STORY_LINKS_CHUNK_SIZE )->hashes;
    select s.*, ts.link_mined, ts.redirect_url
        from snap.live_stories s
            join topic_stories ts on ( s.stories_id = ts.stories_id and s.topics_id = ts.topics_id )
        where
            ts.link_mined = false and
            ts.topics_id = ?
        limit ?
SQL

        my $num_stories = scalar( @{ $stories } );

        last if ( $num_stories == 0 );

        generate_topic_links( $db, $topic, $stories );

        last if ( $num_stories < $EXTRACT_STORY_LINKS_CHUNK_SIZE );
    }
}

# import all topic_seed_urls that have not already been processed;
# return 1 if new stories were added to the topic and 0 if not
sub import_seed_urls($$)
{
    my ( $db, $topic ) = @_;

    INFO( "import seed urls" );

    my $topics_id = $topic->{ topics_id };

    # take care of any seed urls with urls that we have already processed for this topic
    $db->query( <<END, $topics_id );
update topic_seed_urls a set stories_id = b.stories_id, processed = 't'
    from topic_seed_urls b
    where a.url = b.url and
        a.topics_id = ? and b.topics_id = a.topics_id and
        a.stories_id is null and b.stories_id is not null
END

    # randomly shuffle this query so that we don't block the extractor pool by throwing it all
    # stories from a single media_id at once
    my $seed_urls = $db->query( <<END, $topics_id )->hashes;
select * from topic_seed_urls where topics_id = ? and processed = 'f' order by random()
END

    return 0 unless ( @{ $seed_urls } );

    # process these in chunks in case we have to start over so that we don't have to redo the whole batch
    my $num_urls = scalar( @{ $seed_urls } );
    for ( my $i = 0 ; $i < $num_urls ; $i += $ADD_NEW_LINKS_CHUNK_SIZE )
    {
        my $start_time = time;

        update_topic_state( $db, $topic, "importing seed urls: $i / $num_urls" );

        my $end = List::Util::min( $i + $ADD_NEW_LINKS_CHUNK_SIZE - 1, $#{ $seed_urls } );
        my $seed_urls_chunk = [ @{ $seed_urls }[ $i .. $end ] ];
        add_new_links_chunk( $db, $topic, 0, $seed_urls_chunk );

        my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ topic_seed_urls_id } } @{ $seed_urls_chunk } ] );

        # update topic_seed_urls that were actually fetched
        $db->query( <<SQL );
update topic_seed_urls tsu
    set stories_id = tfu.stories_id
    from topic_fetch_urls tfu, $ids_table ids
    where
        tsu.topics_id = tfu.topics_id and
        md5(tsu.url) = md5(tfu.url) and
        tsu.topic_seed_urls_id = ids.id
SQL

        # now update the topic_seed_urls that were matched
        $db->query( <<SQL );
update topic_seed_urls tsu
    set processed = 't'
    from $ids_table ids
    where
        tsu.topic_seed_urls_id = ids.id and
        processed = 'f'
SQL

        my $elapsed_time = time - $start_time;
        save_metrics( $db, $topic, 1, $end - $i, $elapsed_time );
    }

    # cleanup any topic_seed_urls pointing to a merged story
    $db->query(
        <<SQL,
        UPDATE topic_seed_urls AS tsu
        SET stories_id = tms.target_stories_id, processed = 't'
        FROM topic_merged_stories_map AS tms,
             topic_stories ts
        WHERE tsu.stories_id = tms.source_stories_id
          AND ts.stories_id = tms.target_stories_id
          AND tsu.topics_id = ts.topics_id
          AND ts.topics_id = \$1
SQL
        $topic->{ topics_id }
    );

    return scalar( @{ $seed_urls } );
}

# look for any stories in the topic tagged with a date method of 'current_time' and
# assign each the earliest source link date if any source links exist
sub add_source_link_dates
{
    my ( $db, $topic ) = @_;

    INFO( "add source link dates" );

    my $stories = $db->query( <<END, $topic->{ topics_id } )->hashes;
select s.* from stories s, topic_stories cs, tag_sets ts, tags t, stories_tags_map stm
    where s.stories_id = cs.stories_id and cs.topics_id = ? and
        stm.stories_id = s.stories_id and stm.tags_id = t.tags_id and
        t.tag_sets_id = ts.tag_sets_id and
        t.tag in ( 'current_time' ) and ts.name = 'date_guess_method'
END

    for my $story ( @{ $stories } )
    {
        my $source_link = $db->query( <<END, $topic->{ topics_id }, $story->{ stories_id } )->hash;
select cl.*, s.publish_date
        from topic_links cl
            join stories s on ( cl.stories_id = s.stories_id )
    where
        cl.topics_id = ? and
        cl.ref_stories_id = ?
    order by cl.topic_links_id asc
END

        next unless ( $source_link );

        $db->query( <<END, $source_link->{ publish_date }, $story->{ stories_id } );
update stories set publish_date = ? where stories_id = ?
END
        MediaWords::DBI::Stories::GuessDate::assign_date_guess_method( $db, $story, 'source_link' );
    }
}

# insert a list of topic seed urls, using efficient copy
sub insert_topic_seed_urls
{
    my ( $db, $topic_seed_urls ) = @_;

    INFO "inserting " . scalar( @{ $topic_seed_urls } ) . " topic seed urls ...";

    my $columns = [ 'stories_id', 'url', 'topics_id', 'assume_match' ];

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    my $copy_from = $db->copy_from( "COPY topic_seed_urls (" . join( ', ', @{ $columns } ) . ") FROM STDIN WITH CSV" );
    for my $csu ( @{ $topic_seed_urls } )
    {
        $csv->combine( map { $csu->{ $_ } } ( @{ $columns } ) );
        $copy_from->put_line( $csv->string );
    }
    $copy_from->end();
}

# import a single month of the solr seed query.  we do this to avoid giant queries that timeout in solr.
sub import_solr_seed_query_month($$$)
{
    my ( $db, $topic, $month_offset ) = @_;

    return unless ( $topic->{ platform } eq 'web' );

    my $max_stories = $topic->{ max_stories };

    # if solr maxes out on returned stories, it returns a few documents less than the rows= parameter, so we
    # assume that we hit the solr max if we are within 5% of the ma stories
    my $max_returned_stories = $max_stories * 0.95;

    my $solr_query = MediaWords::Solr::Query::get_full_solr_query_for_topic( $db, $topic, undef, undef, $month_offset );

    # this should return undef once the month_offset gets too big
    return undef unless ( $solr_query );

    INFO "import solr seed query month offset $month_offset";
    $solr_query->{ rows } = $max_stories;

    my $stories = MediaWords::Solr::search_for_stories( $db, $solr_query );

    if ( scalar( @{ $stories } ) > $max_returned_stories )
    {
        die( "solr_seed_query returned more than $max_returned_stories stories" );
    }

    INFO "adding " . scalar( @{ $stories } ) . " stories to topic_seed_urls";

    $db->begin;

    my $topic_seed_urls = [];
    for my $story ( @{ $stories } )
    {
        push(
            @{ $topic_seed_urls },
            {
                topics_id    => $topic->{ topics_id },
                url          => $story->{ url },
                stories_id   => $story->{ stories_id },
                assume_match => 'f'
            }
        );
    }

    insert_topic_seed_urls( $db, $topic_seed_urls );

    $db->commit if $db->in_transaction();

    return 1;
}

# import stories intro topic_seed_urls from solr by running
# topic->{ solr_seed_query } against solr.  if the solr query has
# already been imported, do nothing.
sub import_solr_seed_query
{
    my ( $db, $topic ) = @_;

    INFO( "import solr seed query" );

    return if ( $topic->{ solr_seed_query_run } );

    my $month_offset = 0;
    while ( import_solr_seed_query_month( $db, $topic, $month_offset++ ) ) { }

    $db->query( "update topics set solr_seed_query_run = 't' where topics_id = ?", $topic->{ topics_id } );
}

# return true if there are no stories without facebook data
sub all_facebook_data_fetched
{
    my ( $db, $topic ) = @_;

    my $null_facebook_story = $db->query( <<SQL, $topic->{ topics_id } )->hash;
select 1
    from topic_stories cs
        left join story_statistics ss on ( cs.stories_id = ss.stories_id )
    where
        cs.topics_id = ? and
        (
            ss.stories_id is null or
            ss.facebook_share_count is null or
            ss.facebook_comment_count is null or
            ss.facebook_api_collect_date is null
        )
    limit 1
SQL

    return !$null_facebook_story;
}

# add all topic stories without facebook data to the queue
sub __add_topic_stories_to_facebook_queue($$)
{
    my ( $db, $topic ) = @_;

    my $topics_id = $topic->{ topics_id };

    my $stories = $db->query( <<END, $topics_id )->hashes;
SELECT ss.*, cs.stories_id
    FROM topic_stories cs
        left join story_statistics ss on ( cs.stories_id = ss.stories_id )
    WHERE cs.topics_id = ?
    ORDER BY cs.stories_id
END

    unless ( scalar @{ $stories } )
    {
        DEBUG( "No stories found for topic '$topic->{ name }'" );
    }

    for my $ss ( @{ $stories } )
    {
        my $stories_id = $ss->{ stories_id };
        my $args = { stories_id => $stories_id };

        if (   $ss->{ facebook_api_error }
            or !defined( $ss->{ facebook_api_collect_date } )
            or !defined( $ss->{ facebook_share_count } )
            or !defined( $ss->{ facebook_comment_count } ) )
        {
            DEBUG( "Adding job for story $stories_id" );
            MediaWords::JobManager::Job::add_to_queue( 'MediaWords::Job::Facebook::FetchStoryStats', $args );
        }
    }
}

# send high priority jobs to fetch facebook data for all stories that don't yet have it
sub fetch_social_media_data ($$)
{
    my ( $db, $topic ) = @_;

    INFO( "fetch social media data" );

    # test spider should be able to run with job broker, so we skip social media collection
    return if ( $_test_mode );

    my $cid = $topic->{ topics_id };

    __add_topic_stories_to_facebook_queue( $db, $topic );

    my $poll_wait = 30;
    my $retries   = int( $MAX_SOCIAL_MEDIA_FETCH_TIME / $poll_wait ) + 1;

    for my $i ( 1 .. $retries )
    {
        return if ( all_facebook_data_fetched( $db, $topic ) );
        sleep $poll_wait;
    }

    LOGCONFESS( "Timed out waiting for social media data" );
}

# die if the error rate for link extraction or link fetching is too high
sub check_job_error_rate($$)
{
    my ( $db, $topic ) = @_;

    INFO( "check job error rate" );

    my $fetch_stats = $db->query( <<SQL, $topic->{ topics_id } )->hashes();
select count(*) num, ( state = 'python error' ) as error
    from topic_fetch_urls
        where topics_id = ?
        group by ( state = 'python error' )
SQL

    my ( $num_fetch_errors, $num_fetch_successes ) = ( 0, 0 );
    for my $s ( @{ $fetch_stats } )
    {
        if   ( $s->{ error } ) { $num_fetch_errors    += $s->{ num } }
        else                   { $num_fetch_successes += $s->{ num } }
    }

    my $fetch_error_rate = $num_fetch_errors / ( $num_fetch_errors + $num_fetch_successes + 1 );

    INFO( "Fetch error rate: $fetch_error_rate ($num_fetch_errors / $num_fetch_successes)" );

    if ( $fetch_error_rate > $MAX_JOB_ERROR_RATE )
    {
        die( "Fetch error rate of $fetch_error_rate is greater than max of $MAX_JOB_ERROR_RATE" );
    }

    my $link_stats = $db->query( <<SQL, $topic->{ topics_id } )->hashes();
select count(*) num, ( length( link_mine_error) > 0 ) as error
    from topic_stories
        where topics_id = ?
        group by ( length( link_mine_error ) > 0 )
SQL

    my ( $num_link_errors, $num_link_successes ) = ( 0, 0 );
    for my $s ( @{ $link_stats } )
    {
        if   ( $s->{ error } ) { $num_link_errors    += $s->{ num } }
        else                   { $num_link_successes += $s->{ num } }
    }

    my $link_error_rate = $num_link_errors / ( $num_link_errors + $num_link_successes + 1 );

    INFO( "Link error rate: $link_error_rate ($num_link_errors / $num_link_successes)" );

    if ( $link_error_rate > $MAX_JOB_ERROR_RATE )
    {
        die( "link error rate of $link_error_rate is greater than max of $MAX_JOB_ERROR_RATE" );
    }
}

# import urls from seed query 
sub import_urls_from_seed_query($$)
{
    my ( $db, $topic ) = @_;
    
    my $topic_seed_queries = $db->query(
        "select * from topic_seed_queries where topics_id = ?", $topic->{ topics_id } )->hashes();

    my $num_queries = scalar( @{ $topic_seed_queries } );

    my $tsq = $num_queries ? $topic_seed_queries->[0] : undef;
    
    if ( $num_queries > 1 )
    {
        die( "only one topic seed query allowed per topic" );
    }
    elsif ( $num_queries == 0 )
    {
        update_topic_state( $db, $topic, "importing solr seed query" );
        import_solr_seed_query( $db, $topic );
        return;
    }
    elsif ( MediaWords::TM::FetchTopicPosts::get_fetch_posts_function( $tsq ) )
    {
        MediaWords::TM::FetchTopicPosts::fetch_topic_posts( $db, $topic->{ topics_id } );
    }
    else
    {
        die( "unable to import seet urls for platform/mode of seed query: " . Dumper( $tsq ) );
    }
}

# if the query or dates have changed, set topic_stories.link_mined to false for the impacted stories so that
# they will be respidered
sub set_stories_respidering($$$)
{
    my ( $db, $topic, $snapshots_id ) = @_;

    return unless ( $topic->{ respider_stories } );

    my $respider_start_date = $topic->{ respider_start_date };
    my $respider_end_date = $topic->{ respider_end_date };

    if ( !$respider_start_date && !$respider_end_date )
    {
        $db->query( "update topic_stories set link_mined = 'f' where topics_id = ?", $topic->{ topics_id } );
        return;
    }

    $db->begin;

    if ( $respider_start_date )
    {
        $db->query( <<SQL, $respider_start_date, $topic->{ start_date }, $topic->{ topics_id } );
update topic_stories ts set link_mined = 'f'
    from stories s
    where
        ts.stories_id = s.stories_id and
        s.publish_date >= \$2 and 
        s.publish_date <= \$1 and
        ts.topics_id = \$3
SQL
        if ( $snapshots_id )
        {
            $db->update_by_id( 'snapshots', $snapshots_id, { start_date => $topic->{ start_date } } );
            $db->query( <<SQL, $snapshots_id, $respider_start_date );
update timespans set archive_snapshots_id = snapshots_id, snapshots_id = null
    where snapshots_id = ? and start_date < ?
SQL
        }
    }

    if ( $respider_end_date )
    {
        $db->query( <<SQL, $respider_end_date, $topic->{ end_date }, $topic->{ topics_id } );
update topic_stories ts set link_mined = 'f'
    from stories s
    where
        ts.stories_id = s.stories_id and
        s.publish_date >= \$1 and 
        s.publish_date <= \$2 and
        ts.topics_id = \$3
SQL

        if ( $snapshots_id )
        {
            $db->update_by_id( 'snapshots', $snapshots_id, { end_date => $topic->{ end_date } } );
            $db->query( <<SQL, $snapshots_id, $respider_end_date );
update timespans set archive_snapshots_id = snapshots_id, snapshots_id = null
    where snapshots_id = ? and end_date > ?
SQL
        }
    }

    $db->update_by_id( 'topics', $topic->{ topics_id },
        { respider_stories => 'f', respider_start_date => undef, respider_end_date => undef } );

    $db->commit;
}


# mine the given topic for links and to recursively discover new stories on the web.
# options:
#   import_only - only run import_seed_urls and import_solr_seed and exit
#   skip_post_processing - skip social media fetching and snapshotting
#   snapshots_id - associate topic with the given existing snapshot
sub do_mine_topic ($$;$)
{
    my ( $db, $topic, $options ) = @_;

    # if ( !$topic->{ is_story_index_ready } )
    # {
    #     die( "refusing to run topic because is_story_index_ready is false" );
    # }

    map { $options->{ $_ } ||= 0 } qw/import_only skip_post_processing test_mode/;

    update_topic_state( $db, $topic, "importing seed urls" );
    import_urls_from_seed_query( $db, $topic );

    update_topic_state( $db, $topic, "setting stories respidering..." );
    set_stories_respidering( $db, $topic, $options->{ snapshots_id } );

    # this may put entires into topic_seed_urls, so run it before import_seed_urls.
    # something is breaking trying to call this perl.  commenting out for time being since we only need
    # this when we very rarely change the foreign_rss_links field of a media source - hal
    # update_topic_state( $db, $topic, "merging foreign rss stories" );
    # MediaWords::TM::Stories::merge_foreign_rss_stories( $db, $topic );

    update_topic_state( $db, $topic, "importing seed urls" );
    if ( import_seed_urls( $db, $topic ) > $MIN_SEED_IMPORT_FOR_PREDUP_STORIES )
    {
        # merge dup stories before as well as after spidering to avoid extra spidering work
        update_topic_state( $db, $topic, "merging duplicate stories" );
        MediaWords::TM::Stories::find_and_merge_dup_stories( $db, $topic );
    }

    unless ( $options->{ import_only } )
    {
        update_topic_state( $db, $topic, "running spider" );
        run_spider( $db, $topic );

        check_job_error_rate( $db, $topic );

        # merge dup media and stories again to catch dups from spidering
        update_topic_state( $db, $topic, "merging duplicate stories" );
        MediaWords::TM::Stories::find_and_merge_dup_stories( $db, $topic );

        update_topic_state( $db, $topic, "merging duplicate media stories" );
        MediaWords::TM::Stories::merge_dup_media_stories( $db, $topic );

        update_topic_state( $db, $topic, "adding source link dates" );
        add_source_link_dates( $db, $topic );

        if ( !$options->{ skip_post_processing } )
        {
            update_topic_state( $db, $topic, "fetching social media data" );
            fetch_social_media_data( $db, $topic );

            update_topic_state( $db, $topic, "snapshotting" );
            my $snapshot_args = { topics_id => $topic->{ topics_id }, snapshots_id => $options->{ snapshots_id } };
            MediaWords::JobManager::StatefulJob::add_to_queue( 'MediaWords::Job::TM::SnapshotTopic', $snapshot_args );
        }
    }
}

# add the url parsed from a tweet to topics_seed_url
sub add_tweet_seed_url
{
    my ( $db, $topic, $url ) = @_;

    my $existing_seed_url = $db->query( <<SQL, $topic->{ topics_id }, $url );
select * from topic_seed_urls where topics_id = ? and url = ?
SQL

    if ( $existing_seed_url )
    {
        $db->update_by_id( 'topic_seed_urls', $existing_seed_url->{ topic_seed_urls_id }, { assume_match => 't' } );
    }
    else
    {
        $db->create(
            'topic_seed_urls',
            {
                topics_id    => $topic->{ topics_id },
                url          => $url,
                assume_match => 't',
                source       => 'twitter',
            }
        );
    }
}

# insert all topic_tweet_urls into topic_seed_urls for twitter child toic
sub seed_topic_with_tweet_urls($$)
{
    my ( $db, $topic ) = @_;

    INFO( "seed topic with tweet urls" );

    # update any already existing urls to be assume_match = 't'
    $db->query( <<SQL, $topic->{ topics_id } );
update topic_seed_urls tsu
    set assume_match = 't', processed = 'f'
    from
        topic_tweet_full_urls ttfu
    where
        ttfu.topics_id = tsu.topics_id  and
        ttfu.url = tsu.url and
        tsu.topics_id = \$1 and
        assume_match = false
SQL

    # now insert any topic_tweet_urls that are not already in the topic_seed_urls.
    # ignore pb.twimg.com urls because they are almost all images and their servers hang the downloader
    # when we try to download them en masse
    $db->query(
        <<SQL,
        INSERT INTO topic_seed_urls ( topics_id, url, assume_match, source )
            SELECT DISTINCT ttfu.topics_id, ttfu.url, true, 'twitter'
            FROM topic_tweet_full_urls ttfu
            WHERE ttfu.topics_id = \$1
              AND ttfu.url NOT IN (
                SELECT url
                FROM topic_seed_urls
                WHERE topics_id = \$1
              )
              AND not ttfu.url like 'https://twitter.com%'
              AND not ttfu.url like '%pbs.twimg.com%'
SQL
        $topic->{ topics_id }
    );
}

# if this is a twitter topic, fetch the twitter data
sub fetch_and_import_twitter_urls($$)
{
    my ( $db, $topic ) = @_;

    return unless ( $topic->{ platform } eq 'twitter' );

    MediaWords::TM::FetchTopicPosts::fetch_topic_posts( $db, $topic->{ topics_id } );

    seed_topic_with_tweet_urls( $db, $topic );
}

# wrap do_mine_topic in eval and handle errors and state
sub mine_topic ($$;$)
{
    my ( $db, $topic, $options ) = @_;

    my $prev_test_mode = $_test_mode;

    $_test_mode = 1 if ( $options->{ test_mode } );

    if ( $topic->{ state } ne 'running' )
    {
        MediaWords::TM::Alert::send_topic_alert( $db, $topic, "started topic spidering" );
    }

    eval { do_mine_topic( $db, $topic, $options ); };
    if ( $@ )
    {
        my $error = $@;
        MediaWords::TM::Alert::send_topic_alert( $db, $topic, "aborted topic spidering due to error" );
        LOGDIE( $error );
    }

    $_test_mode = $prev_test_mode;
}

1;
