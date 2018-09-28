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

import_python_module( __PACKAGE__, 'mediawords.tm.mine' );

use Carp;
use Data::Dumper;
use DateTime;
use Digest::MD5;
use Encode;
use Getopt::Long;
use HTML::Entities;
use Inline::Python;
use List::Util;
use Parallel::ForkManager;
use Readonly;
use Time::Piece;
use Time::Seconds;
use URI;
use URI::Escape;

use MediaWords::CommonLibs;

use MediaWords::TM;
use MediaWords::TM::FetchTopicTweets;
use MediaWords::TM::FetchLink;
use MediaWords::TM::GuessDate;
use MediaWords::TM::GuessDate::Result;
use MediaWords::TM::Snapshot;
use MediaWords::TM::Stories;
use MediaWords::DB;
use MediaWords::DB::Locks;
use MediaWords::DBI::Activities;
use MediaWords::DBI::Media;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::GuessDate;
use MediaWords::Job::ExtractAndVector;
use MediaWords::Job::Facebook::FetchStoryStats;
use MediaWords::Job::TM::ExtractStoryLinks;
use MediaWords::Job::TM::FetchLink;
use MediaCloud::JobManager::Job;
use MediaWords::Languages::Language;
use MediaWords::Solr;
use MediaWords::Util::Config;
use MediaWords::Util::IdentifyLanguage;
use MediaWords::Util::SQL;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;
use MediaWords::Util::Web;
use MediaWords::Util::Web::Cache;

# total time to wait for fetching of social media metrics
Readonly my $MAX_SOCIAL_MEDIA_FETCH_TIME => ( 60 * 60 * 24 );

# add new links in chunks of this size
Readonly my $ADD_NEW_LINKS_CHUNK_SIZE => 10_000;

# extract story links in chunks of this size
Readonly my $EXTRACT_STORY_LINKS_CHUNK_SIZE => 1000;

# query this many topic_links at a time to spider
Readonly my $SPIDER_LINKS_CHUNK_SIZE => 100_000;

# die if the error rate for link fetch or link extract jobs is greater than this
Readonly my $MAX_JOB_ERROR_RATE => 0.01;

# timeout when polling for jobs to finish
Readonly my $JOB_POLL_TIMEOUT => 3600;

# number of seconds to wait when polling for jobs to finish
Readonly my $JOB_POLL_WAIT => 5;

# if more than this many seed urls are imported, dedup stories before as well as after spidering
Readonly my $MIN_SEED_IMPORT_FOR_PREDUP_STORIES => 50_000;

# if mine_topic is run with the test_mode option, set this true and do not try to queue extractions
my $_test_mode;

# cache of media by media id
my $_media_cache = {};

# cache for spidered:spidered tag
my $_spidered_tag;

# cache of media by sanitized url
my $_media_url_lookup;

# cache that indicates whether we should recheck a given url
my $_no_potential_match_urls = {};

my $_link_extractor;

# initialize static variables for each run
sub init_static_variables
{
    $_media_cache             = {};
    $_spidered_tag            = undef;
    $_media_url_lookup        = undef;
    $_no_potential_match_urls = {};
}

# update topics.state in the database
sub update_topic_state($$$;$)
{
    my ( $db, $topic, $message ) = @_;

    INFO( "update topic state: $message" );

    eval { MediaWords::Job::TM::MineTopic->update_job_state_message( $db, $message ) };
    if ( $@ )
    {
        die( "error updating job state (mine_topic() must be called from MediaWords::Job::TM::MineTopic): $@" );
    }
}

sub get_cached_medium_by_id
{
    my ( $db, $media_id ) = @_;

    if ( my $medium = $_media_cache->{ $media_id } )
    {
        TRACE "media cache hit";
        return $medium;
    }

    TRACE "media cache miss";
    $_media_cache->{ $media_id } = $db->query( <<SQL, $media_id )->hash;
select *,
        exists ( select 1 from media d where d.dup_media_id = m.media_id ) is_dup_target
    from media m
    where m.media_id = ?
SQL

    return $_media_cache->{ $media_id };
}

# get the html for the first download of the story.  fix the story download by redownloading
# as necessary
sub get_first_download_content
{
    my ( $db, $story ) = @_;

    my $download = $db->query( <<END, $story->{ stories_id } )->hash;
select d.* from downloads d where stories_id = ? order by downloads_id asc limit 1
END

    my $content;
    eval { $content = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };
    if ( $@ )
    {
        MediaWords::DBI::Stories::fix_story_downloads_if_needed( $db, $story );
        $download = $db->find_by_id( 'downloads', int( $download->{ downloads_id } ) );
        eval { $content = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };
        WARN "Error refetching content: $@" if ( $@ );
    }

    return defined $content ? $content : '';
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

# insert a list of topic links, using efficient copy
sub insert_topic_links
{
    my ( $db, $topic_links ) = @_;

    my $columns = [ 'stories_id', 'url', 'topics_id' ];

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    my $copy_from = $db->copy_from( "COPY topic_links (" . join( ', ', @{ $columns } ) . ") FROM STDIN WITH CSV" );
    for my $topic_link ( @{ $topic_links } )
    {
        $csv->combine( map { $topic_link->{ $_ } } ( @{ $columns } ) );
        $copy_from->put_line( encode( 'utf8', $csv->string ) );
    }
    $copy_from->end();
}

# submit jobs to extract links from the given stories and then poll to wait for the stories to be processed within
# the jobs pool
sub generate_topic_links
{
    my ( $db, $topic, $stories ) = @_;

    INFO "generate topic links: " . scalar( @{ $stories } );

    my $topic_links = [];

    if ( $topic->{ ch_monitor_id } )
    {
        INFO( "skip link generation for twitter topic" );
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

        do
        {
            eval {
                MediaWords::Job::TM::ExtractStoryLinks->add_to_queue(
                    { stories_id => $story->{ stories_id }, topics_id => $topic->{ topics_id } } );
            };
            ( sleep( 1 ) && INFO( 'waiting for rabbit ...' ) ) if ( error_is_amqp( $@ ) );
        } until ( !error_is_amqp( $@ ) );

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
            LOGDIE( "Timed out waiting for story link extraction." );
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

# lookup or create the spidered:spidered tag
sub get_spidered_tag
{
    my ( $db ) = @_;

    return $_spidered_tag if ( $_spidered_tag );

    $_spidered_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'spidered:spidered' );

    return $_spidered_tag;
}

# add medium to media_url_lookup
sub add_medium_to_url_lookup
{
    my ( $medium ) = @_;

    $_media_url_lookup->{ MediaWords::Util::URL::normalize_url_lossy( $medium->{ url } ) } = $medium;
}

# derive the url and a media source name from the given story's url
sub generate_medium_url_and_name_from_url
{
    my ( $story_url ) = @_;

    my $normalized_url = MediaWords::Util::URL::normalize_url_lossy( $story_url );

    if ( !( $normalized_url =~ m~(http.?://([^/]+))~i ) )
    {
        WARN "Unable to find host name in url: $normalized_url ($story_url)";
        return ( $story_url, $story_url );
    }

    my ( $medium_url, $medium_name ) = ( $1, $2 );

    $medium_url  = lc( $medium_url );
    $medium_name = lc( $medium_name );

    $medium_url .= "/" unless ( $medium_url =~ /\/$/ );

    return ( $medium_url, $medium_name );

}

# get the first feed found for the given medium
sub get_spider_feed
{
    my ( $db, $medium ) = @_;

    my $feed_query = <<"END";
select * from feeds
    where media_id = ? and url = ?
    order by ( name = 'Spider Feed' )
END

    my $feed = $db->query( $feed_query, $medium->{ media_id }, $medium->{ url } )->hash;

    return $feed if ( $feed );

    $db->query(
        "insert into feeds ( media_id, url, name, active ) " . "  values ( ?, ?, 'Spider Feed', 'f' )",
        $medium->{ media_id },
        $medium->{ url }
    );

    return $db->query( $feed_query, $medium->{ media_id }, $medium->{ url } )->hash;
}

# extract the story for the given download
sub extract_download($$$)
{
    my ( $db, $download, $story ) = @_;

    return if ( $download->{ url } =~ /jpg|pdf|doc|mp3|mp4|zip|png|docx$/i );

    return if ( $download->{ url } =~ /livejournal.com\/(tag|profile)/i );

    my $dt = $db->query( "select 1 from download_texts where downloads_id = ?", $download->{ downloads_id } )->hash;
    return if ( $dt );

    my $extractor_args = MediaWords::DBI::Stories::ExtractorArguments->new(
        {
            no_dedup_sentences => 0,
            use_cache          => 1,
            use_existing       => 1,
        }
    );

    eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, $extractor_args ); };

    if ( my $error = $@ )
    {
        WARN "extract error processing download $download->{ downloads_id }: $error";
    }

    return 1;
}

# recursively search for the medium pointed to by dup_media_id
# by the media_id medium.  return the first medium that does not have a dup_media_id.
sub get_dup_medium
{
    my ( $db, $media_id, $allow_foreign_rss_links, $count ) = @_;

    LOGCROAK( "loop detected in duplicate media graph" ) if ( $count && ( $count > 10 ) );

    return undef unless ( $media_id );

    my $medium = get_cached_medium_by_id( $db, $media_id );

    if ( $medium->{ dup_media_id } )
    {
        return get_dup_medium( $db, $medium->{ dup_media_id }, $allow_foreign_rss_links, ++$count );
    }

    return undef if ( !$allow_foreign_rss_links && $medium->{ foreign_rss_links } );

    return $medium;
}

# return true if we should ignore redirects to the target media source, usually
# to avoid redirects to domainresellers for previously valid and important but now dead
# links
sub ignore_redirect
{
    my ( $db, $link ) = @_;

    unless ( $link->{ redirect_url }
        && ( !MediaWords::Util::URL::urls_are_equal( $link->{ redirect_url }, $link->{ url } ) ) )
    {
        return 0;
    }

    my ( $medium_url, $medium_name ) = generate_medium_url_and_name_from_url( $link->{ redirect_url } );

    my $u = MediaWords::Util::URL::normalize_url_lossy( $medium_url );

    my $match = $db->query( "select 1 from topic_ignore_redirects where url = ?", $u )->hash;

    return $match ? 1 : 0;
}

# wrap create story in eval
sub safely_create_story
{
    my ( $db, $story ) = @_;

    eval { $story = $db->create( 'stories', $story ) };
    LOGCARP( $@ . " - " . Dumper( $story ) ) if ( $@ );

    return $story;
}

# create and return download object in database for the new story
sub create_download_for_new_story
{
    my ( $db, $story, $feed ) = @_;

    my $download = {
        feeds_id   => $feed->{ feeds_id },
        stories_id => $story->{ stories_id },
        url        => $story->{ url },
        host       => MediaWords::Util::URL::get_url_host( $story->{ url } ),
        type       => 'content',
        sequence   => 1,
        state      => 'success',
        path       => 'content:pending',
        priority   => 1,
        extracted  => 't'
    };

    $download = $db->create( 'downloads', $download );

    return $download;
}

# send story to the extraction queue in the hope that it will already be extracted by the time we get to the extraction
# step later in add_new_links_chunk process.
sub queue_extraction($$)
{
    my ( $db, $stories_id ) = @_;

    return if ( $_test_mode );

    my $args = {
        stories_id => $stories_id,
        use_cache  => 1
    };

    my $priority = $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_HIGH;
    eval { MediaWords::Job::ExtractAndVector->add_to_queue( $args, $priority ) };
    ERROR( "error queueing extraction: $@" ) if ( $@ );
}

# return true if any of the story_sentences with no duplicates for the story matches the topic search pattern
sub story_sentence_matches_pattern
{
    my ( $db, $story, $topic ) = @_;

    my $ss = $db->query( <<END, $story->{ stories_id }, $topic->{ topics_id } )->hash;
select 1
    from story_sentences ss
        join topics c on ( c.topics_id = \$2 )
    where
        ss.stories_id = \$1 and
        ss.sentence ~ ( '(?isx)' || c.pattern ) and
        ( ( is_dup is null ) or not ss.is_dup )
    limit 1
END

    return $ss ? 1 : 0;
}

sub _get_sentences_from_story_text
{
    my ( $story_text, $story_lang ) = @_;

    # Tokenize into sentences
    my $lang = MediaWords::Languages::Language::language_for_code( $story_lang );
    if ( !$lang )
    {
        $lang = MediaWords::Languages::Language::default_language();
    }

    my $sentences = $lang->split_text_to_sentences( $story_text );

    return $sentences;
}

# return true if this url already failed a potential match, so we don't have to download it again
sub url_failed_potential_match
{
    my ( $db, $topic, $url ) = @_;

    my ( $failed ) = $db->query(
        "select 1 from topic_fetch_urls where topics_id = ? and url = ? and state in ( ?, ? )",
        $topic->{ 'topics_id' },
        $url,
        $MediaWords::TM::Stories::FETCH_STATE_REQUEST_FAILED,
        $MediaWords::TM::Stories::FETCH_STATE_CONTENT_MATCH_FAILED
    )->flat();

    return $failed;
}

# return the type of match if the story title, url, description, or sentences match topic search pattern.
# return undef if no match is found.
sub story_matches_topic_pattern
{
    my ( $db, $topic, $story, $metadata_only ) = @_;

    my $meta_values = [ map { $story->{ $_ } } qw/title description url redirect_url/ ];

    my $match = $db->query( <<SQL, $topic->{ topics_id }, @{ $meta_values } )->hash;
select 1
    from topics t
    where
        t.topics_id = \$1 and
        (
            ( \$2 ~ ( '(?isx)' || t.pattern ) ) or
            ( \$3 ~ ( '(?isx)' || t.pattern ) ) or
            ( \$4 ~ ( '(?isx)' || t.pattern ) ) or
            ( \$5 ~ ( '(?isx)' || t.pattern ) )
        )
SQL

    return 'meta' if $match;

    return 'sentence' if ( !$metadata_only && ( story_sentence_matches_pattern( $db, $story, $topic ) ) );

    return 0;
}

my $_max_stories_check_count = 0;

# die() with an appropriate error if topic_stories > topics.max_stories; because this check is expensive and we don't
# care if the topic goes over by a few thousand stories, we only actually run the check randmly 1/1000 of the time
sub die_if_max_stories_exceeded($$)
{
    my ( $db, $topic ) = @_;

    return if ( $_max_stories_check_count++ % 1000 );

    my ( $num_topic_stories ) = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select count(*) from topic_stories where topics_id = ?
SQL

    if ( $num_topic_stories > $topic->{ max_stories } )
    {
        LOGDIE( "topic has $num_topic_stories stories, which exceeds topic max stories of $topic->{ max_stories }" );
    }
}

# add to topic_stories table
sub add_to_topic_stories
{
    my ( $db, $topic, $story, $iteration, $link_mined, $valid_foreign_rss_story ) = @_;

    die_if_max_stories_exceeded( $db, $topic );

    $db->query(
        "insert into topic_stories ( topics_id, stories_id, iteration, redirect_url, link_mined, valid_foreign_rss_story ) "
          . "  values ( ?, ?, ?, ?, ?, ? )",
        $topic->{ topics_id },
        $story->{ stories_id },
        $iteration,
        $story->{ url },
        normalize_boolean_for_db( $link_mined ),
        normalize_boolean_for_db( $valid_foreign_rss_story )
    );
}

# return true if the domain of the story url matches the domain of the medium url
sub _story_domain_matches_medium
{
    my ( $db, $medium, $url, $redirect_url ) = @_;

    my $medium_domain = MediaWords::Util::URL::get_url_distinctive_domain( $medium->{ url } );

    my $story_domains = [ map { MediaWords::Util::URL::get_url_distinctive_domain( $_ ) } ( $url, $redirect_url ) ];

    return ( grep { $medium_domain eq $_ } @{ $story_domains } ) ? 1 : 0;
}

# query the database for a count of sentences for each story
sub get_story_with_most_sentences($$)
{
    my ( $db, $stories ) = @_;

    LOGCONFESS( "no stories" ) unless ( scalar( @{ $stories } ) );

    return $stories->[ 0 ] unless ( scalar( @{ $stories } ) > 1 );

    my $stories_id_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my ( $stories_id ) = $db->query( <<SQL )->flat;
select stories_id
    from story_sentences
    where stories_id in ($stories_id_list)
    group by stories_id
    order by count(*) desc
    limit 1
SQL

    $stories_id ||= $stories->[ 0 ]->{ stories_id };

    map { return $_ if ( $_->{ stories_id } eq $stories_id ) } @{ $stories };

    LOGCONFESS( "unable to find story '$stories_id'" );
}

# given a set of possible story matches, find the story that is likely the best.
# the best story is the one that first belongs to the media source that sorts first
# according to the following criteria, in descending order of importance:
# * media pointed to by some dup_media_id;
# * media with a dup_media_id;
# * media whose url domain matches that of the story;
# * media with a lower media_id
#
# within a media source, the preferred story is the one with the most sentences.
sub get_preferred_story
{
    my ( $db, $url, $redirect_url, $stories ) = @_;

    return undef unless ( @{ $stories } );

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };
    $stories = [ values( %{ $stories_lookup } ) ];

    return $stories->[ 0 ] if ( scalar( @{ $stories } ) == 1 );

    TRACE "get_preferred_story: " . scalar( @{ $stories } );

    my $media_lookup = {};
    for my $story ( @{ $stories } )
    {
        my $medium = $media_lookup->{ $story->{ media_id } };
        if ( !$medium )
        {
            $medium = get_cached_medium_by_id( $db, $story->{ media_id } );
            $medium->{ is_dup_source } = $medium->{ dup_media_id } ? 1 : 0;
            $medium->{ matches_domain } = _story_domain_matches_medium( $db, $medium, $url, $redirect_url );
            $media_lookup->{ $medium->{ media_id } } = $medium;
            $medium->{ stories } = [ $story ];
        }
        else
        {
            push( @{ $medium->{ stories } }, $story );
        }
    }

    my $media = [ values %{ $media_lookup } ];

    sub _compare_media
    {
             ( $b->{ is_dup_target } <=> $a->{ is_dup_target } )
          || ( $b->{ is_dup_source } <=> $a->{ is_dup_source } )
          || ( $b->{ matches_domain } <=> $a->{ matches_domain } )
          || ( $a->{ media_id } <=> $b->{ media_id } );
    }

    my $sorted_media = [ sort _compare_media @{ $media } ];

    my $preferred_story = get_story_with_most_sentences( $db, $sorted_media->[ 0 ]->{ stories } );

    TRACE "get_preferred_story done";

    return $preferred_story;
}

# return true if the story is already in topic_stories
sub story_is_topic_story
{
    my ( $db, $topic, $story ) = @_;

    my ( $is_old ) = $db->query(
        "select 1 from topic_stories where stories_id = ? and topics_id = ?",
        $story->{ stories_id },
        $topic->{ topics_id }
    )->flat;

    TRACE "existing topic story: $story->{ url }" if ( $is_old );

    return $is_old;
}

sub set_topic_link_ref_story
{
    my ( $db, $story, $topic_link ) = @_;

    return unless ( $topic_link->{ topic_links_id } );

    my $link_exists = $db->query( <<END, $story->{ stories_id }, $topic_link->{ topic_links_id } )->hash;
select 1
    from topic_links a,
        topic_links b
    where
        a.stories_id = b.stories_id and
        a.topics_id = b.topics_id and
        a.ref_stories_id = ? and
        b.topic_links_id = ?
END

    if ( $link_exists )
    {
        $db->delete_by_id( 'topic_links', $topic_link->{ topic_links_id } );
    }
    else
    {
        $db->query( <<END, $story->{ stories_id }, $topic_link->{ topic_links_id } );
update topic_links set ref_stories_id = ? where topic_links_id = ?
END
        $topic_link->{ ref_stories_id } = $story->{ stories_id };
    }
}

# given a list of stories and a list of links, assign a { link } field to each story based on the
# { stories_id } field in the link
sub add_links_to_stories($$)
{
    my ( $stories, $links ) = @_;

    my $link_lookup = {};
    map { $link_lookup->{ $_->{ stories_id } } = $_ } grep { $_->{ stories_id } } @{ $links };

    map { $_->{ link } = $link_lookup->{ $_->{ stories_id } } } @{ $stories };

    WARN( Dumper( [ map { [ $_->{ stories_id }, $_->{ link } ] } @{ $stories } ] ) );

}

# return true if the $@ error is defined and matches 'AMQP socket not connected'
sub error_is_amqp($)
{
    my ( $error ) = @_;

    return ( $error && ( $error =~ /AMQP socket not connected/ ) );
}

# add the topic_fetch_url to the fetch_link job queue.  try repeatedly on failure.
sub queue_topic_fetch_url($)
{
    my ( $tfu ) = @_;

    my $fetch_link_domain_timeout = $_test_mode ? 0 : undef;

    do
    {
        eval {
            MediaWords::Job::TM::FetchLink->add_to_queue(
                {
                    topic_fetch_urls_id => $tfu->{ topic_fetch_urls_id },
                    domain_timeout      => $fetch_link_domain_timeout
                }
            );
        };
        ( sleep( 1 ) && DEBUG( 'waiting for rabbit ...' ) ) if ( error_is_amqp( $@ ) );
    } until ( !error_is_amqp( $@ ) );
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

# fetch the given links by creating topic_fetch_urls rows and sending them to the MediaWords::Job::TM::FetchLink queue
# for processing.  wait for the queue to complete and returnt the resulting topic_fetch_urls.
sub fetch_links
{
    my ( $db, $topic, $fetch_links ) = @_;

    INFO( "fetch_links: queue links" );
    my $tfus = create_and_queue_topic_fetch_urls( $db, $topic, $fetch_links );
    my $num_queued_links = scalar( @{ $fetch_links } );

    INFO( "waiting for fetch link queue: $num_queued_links queued" );

    my $tfu_ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ topic_fetch_urls_id } ) } @{ $tfus } ] );

    # now poll waiting for the queue to clear
    my $requeues         = 0;
    my $max_requeues     = 3;
    my $max_requeue_jobs = 10;
    my $requeue_timeout  = 300;

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

        my $time_since_change = time() - $last_pending_change;

        # for some reason, the fetch_link queue is occasionally losing a small number of jobs.  until we can
        # find the cause of the bug, just requeue stray jobs a few times
        if (   ( $time_since_change > $requeue_timeout )
            && ( $requeues < $max_requeues )
            && ( $num_pending_urls < $max_requeue_jobs ) )
        {
            INFO( "requeueing fetch_link $num_pending_urls jobs ... [requeue $requeues]" );
            map { queue_topic_fetch_url( $db->require_by_id( 'topic_fetch_urls', $_ ) ) } @{ $pending_url_ids };
            ++$requeues;
            $last_pending_change = time();
        }

        if ( $time_since_change > $JOB_POLL_TIMEOUT )
        {
            splice( @{ $pending_url_ids }, 10 );
            my $ids_list = join( ', ', @{ $pending_url_ids } );
            die( "Timed out waiting for fetch_link queue ($ids_list)" );
        }

        $last_pending_change = time() if ( $num_pending_urls < $last_num_pending_urls );

        $last_num_pending_urls = $num_pending_urls;

        sleep( $JOB_POLL_WAIT );
    }

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

# return the stories from the list that have no download texts associated with them.  attach a download to each story
sub filter_and_attach_downloads_to_extract_stories($$)
{
    my ( $db, $stories ) = @_;

    INFO( "filter and attach downloads to extract stories" );

    my $stories_ids = [ map { int( $_->{ stories_id } ) } @{ $stories } ];

    my $ids_table = $db->get_temporary_ids_table( $stories_ids );

    my $downloads = $db->query( <<SQL )->hashes;
select d.*
    from downloads d
        left join download_texts dt on ( d.downloads_id = dt.downloads_id )
    where
        dt.downloads_id is null and
        d.stories_id in ( select id from $ids_table )
SQL

    $db->query( "discard temp" );

    my $downloads_lookup = {};
    map { $downloads_lookup->{ $_->{ stories_id } } = $_ } @{ $downloads };

    map { $_->{ download } = $downloads_lookup->{ $_->{ stories_id } } } @{ $stories };

    return [ grep { $_->{ download } } @{ $stories } ];
}

# extract new stories in the list of topic_fetch_urls
sub extract_fetched_stories
{
    my ( $db, $tfus ) = @_;

    INFO( "extract fetched stories" );

    my $tfu_ids_table = $db->get_temporary_ids_table( [ map { $_->{ topic_fetch_urls_id } } @{ $tfus } ] );
    my $stories = $db->query( <<SQL )->hashes();
select s.*
    from stories s
        join topic_fetch_urls tfu using ( stories_id )
    where
        topic_fetch_urls_id in ( select id from $tfu_ids_table )
SQL

    # queue exrtactions first so that the extractor job pool can extract and cache some of the below extractions
    map { queue_extraction( $db, $_->{ stories_id } ) } @{ $stories };

    INFO "possible extract stories: " . scalar( @{ $stories } );

    $stories = filter_and_attach_downloads_to_extract_stories( $db, $stories );

    INFO "extract stories: " . scalar( @{ $stories } );

    my $local_extracts = 0;
    for my $story ( @{ $stories } )
    {
        TRACE "extract story: " . $story->{ url };
        if ( extract_download( $db, $story->{ download }, $story ) )
        {
            $local_extracts += 1;
        }
    }

    INFO "local extracts: " . $local_extracts;
}

# download any unmatched link in new_links, add it as a story, extract it, add any links to the topic_links list.
# each hash within new_links can either be a topic_links hash or simply a hash with a { url } field.  if
# the link is a topic_links hash, the topic_link will be updated in the database to point ref_stories_id
# to the new link story.  For each link, set the { story } field to the story found or created for the link.
sub add_new_links_chunk($$$$)
{
    my ( $db, $topic, $iteration, $new_links ) = @_;

    INFO( "add_new_links_chunk: fetch_links" );
    my $topic_fetch_urls = fetch_links( $db, $topic, $new_links );

    INFO( "add_new_links_chunk: extract_fetched_stories" );
    extract_fetched_stories( $db, $topic_fetch_urls );

    INFO( "add_new_links_chunk: add_to_topic_stories_if_match" );
    map { add_to_topic_stories_if_match( $db, $topic, $_, $iteration ) } @{ $topic_fetch_urls };

    INFO( "add_new_links_chunk: mark topic links spidered" );
    my $link_ids_table = $db->get_temporary_ids_table( [ grep { $_ } map { $_->{ topic_links_id } } @{ $new_links } ] );
    $db->query( <<SQL );
update topic_links set link_spidered  = 't' where topic_links_id in ( select id from $link_ids_table )
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

    my $num_iterations = $topic->{ max_iterations };

    for my $i ( 1 .. $num_iterations )
    {
        spider_new_links( $db, $topic, $i );
    }
}

# delete any stories belonging to one of the archive site sources and set any links to archive stories
# to null ref_stories_id so that they will be respidered.  this allows us to respider any archive stories
# left over before implementation of archive site redirects
sub cleanup_existing_archive_stories($$)
{
    my ( $db, $topic ) = @_;

    INFO( "cleanup existing archive stories" );

    my $archive_media_ids = $db->query( <<SQL )->flat;
select media_id from media where name in ( 'is', 'linkis.com', 'archive.org' )
SQL

    return unless ( @{ $archive_media_ids } );

    my $media_ids_list = join( ',', @{ $archive_media_ids } );

    $db->query( <<SQL, $topic->{ topics_id } );
update topic_links tl set ref_stories_id = null
    from snap.live_stories s
    where
        tl.ref_stories_id = s.stories_id and
        tl.topics_id = s.topics_id and
        tl.topics_id = ? and
        s.media_id in ( $media_ids_list )
SQL

    $db->query( <<SQL, $topic->{ topics_id } );
delete from topic_stories ts
    using stories s
    where
        ts.stories_id = s.stories_id and
        ts.topics_id = ? and
        s.media_id in ( $media_ids_list )
SQL

}

# mine for links any stories in topic_stories for this topic that have not already been mined
sub mine_topic_stories
{
    my ( $db, $topic ) = @_;

    INFO( "mine topic stories" );

    cleanup_existing_archive_stories( $db, $topic );

    # check for twitter topic here as well as in generate_topic_links, because the below query grows very
    # large without ever mining links
    if ( $topic->{ ch_monitor_id } )
    {
        INFO( "skip link generation for twitter topic" );
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

# get the smaller iteration of the two stories
sub get_merged_iteration
{
    my ( $db, $topic, $delete_story, $keep_story ) = @_;

    my $cid = $topic->{ topics_id };
    my $i = $db->query( <<END, $cid, $delete_story->{ stories_id }, $keep_story->{ stories_id } )->flat;
select iteration
    from topic_stories
    where
        topics_id  = \$1 and
        stories_id in ( \$2, \$3 )
END

    return List::Util::min( @{ $i } );
}

# merge delete_story into keep_story by making sure all links that are in delete_story are also in keep_story and making
# sure that keep_story is in topic_stories.  once done, delete delete_story from topic_stories (but not from
# stories)
sub merge_dup_story
{
    my ( $db, $topic, $delete_story, $keep_story ) = @_;

    TRACE( <<END );
dup $keep_story->{ title } [ $keep_story->{ stories_id } ] <- $delete_story->{ title } [ $delete_story->{ stories_id } ]
END

    if ( $delete_story->{ stories_id } == $keep_story->{ stories_id } )
    {
        TRACE( "refusing to merge identical story" );
        return;
    }

    my $topics_id = $topic->{ topics_id };

    my $ref_topic_links = $db->query( <<END, $delete_story->{ stories_id }, $topics_id )->hashes;
select * from topic_links where ref_stories_id = ? and topics_id = ?
END

    for my $ref_topic_link ( @{ $ref_topic_links } )
    {
        set_topic_link_ref_story( $db, $keep_story, $ref_topic_link );
    }

    if ( !story_is_topic_story( $db, $topic, $keep_story ) )
    {
        my $merged_iteration = get_merged_iteration( $db, $topic, $delete_story, $keep_story );
        add_to_topic_stories( $db, $topic, $keep_story, $merged_iteration, 1 );
    }

    my $use_transaction = !$db->in_transaction();
    $db->begin if ( $use_transaction );

    my $topic_links = $db->query( <<END, $delete_story->{ stories_id }, $topics_id )->hashes;
select * from topic_links where stories_id = ? and topics_id = ?
END

    for my $topic_link ( @{ $topic_links } )
    {
        my ( $link_exists ) =
          $db->query( <<END, $keep_story->{ stories_id }, $topic_link->{ ref_stories_id }, $topics_id )->hash;
select * from topic_links where stories_id = ? and ref_stories_id = ? and topics_id = ?
END

        if ( !$link_exists )
        {
            $db->query( <<END, $keep_story->{ stories_id }, $topic_link->{ topic_links_id } );
update topic_links set stories_id = ? where topic_links_id = ?
END
        }
    }

    $db->query( <<END, $delete_story->{ stories_id }, $topics_id );
delete from topic_stories where stories_id = ? and topics_id = ?
END

    $db->query( <<END, $delete_story->{ stories_id }, $keep_story->{ stories_id } );
insert into topic_merged_stories_map ( source_stories_id, target_stories_id ) values ( ?, ? )
END

    $db->query( <<END, $delete_story->{ stories_id }, $keep_story->{ stories_id }, $topic->{ topics_id } );
update topic_seed_urls set stories_id = \$2 where stories_id = \$1 and topics_id = \$3
END

    $db->commit if ( $use_transaction );
}

# clone the given story, assigning the new media_id and copying over the download, extracted text, and so on
sub clone_story
{
    my ( $db, $topic, $old_story, $new_medium ) = @_;

    my $story = {
        url          => $old_story->{ url },
        media_id     => $new_medium->{ media_id },
        guid         => $old_story->{ guid },
        publish_date => $old_story->{ publish_date },
        collect_date => MediaWords::Util::SQL::sql_now,
        description  => $old_story->{ description },
        title        => $old_story->{ title }
    };

    $story = safely_create_story( $db, $story );
    add_to_topic_stories( $db, $topic, $story, 0, 1 );

    $db->query( <<SQL, $story->{ stories_id }, $old_story->{ stories_id } );
insert into stories_tags_map ( stories_id, tags_id )
    select \$1, stm.tags_id from stories_tags_map stm where stm.stories_id = \$2
SQL

    my $feed = get_spider_feed( $db, $new_medium );
    $db->create( 'feeds_stories_map', { feeds_id => $feed->{ feeds_id }, stories_id => $story->{ stories_id } } );

    my $download = create_download_for_new_story( $db, $story, $feed );

    my $content = get_first_download_content( $db, $old_story );

    $download = MediaWords::DBI::Downloads::store_content( $db, $download, $content );

    $db->query( <<SQL, $download->{ downloads_id }, $old_story->{ stories_id } );
insert into download_texts ( downloads_id, download_text, download_text_length )
    select \$1, dt.download_text, dt.download_text_length
        from download_texts dt
            join downloads d on ( dt.downloads_id = d.downloads_id )
        where d.stories_id = \$2
        order by d.downloads_id asc
        limit 1
SQL

    $db->query( <<SQL, $story->{ stories_id }, $old_story->{ stories_id } );
insert into story_sentences ( stories_id, sentence_number, sentence, media_id, publish_date, language )
    select \$1, sentence_number, sentence, media_id, publish_date, language
        from story_sentences
        where stories_id = \$2
SQL

    return $story;
}

# given a story in a dup_media_id medium, look for or create a story in the medium pointed to by dup_media_id
sub merge_dup_media_story
{
    my ( $db, $topic, $story ) = @_;

    # allow foreign_rss_links get get_dup_medium, because at this point the only
    # foreign_rss_links stories should have been added by add_outgoing_foreign_rss_links
    my $dup_medium = get_dup_medium( $db, $story->{ media_id }, 1 );

    WARN "No dup medium found" unless ( $dup_medium );

    return unless ( $dup_medium );

    my $new_story = $db->query(
        <<END, $dup_medium->{ media_id }, $story->{ url }, $story->{ guid }, $story->{ title }, $story->{ publish_date } )->hash;
SELECT s.* FROM stories s
    WHERE s.media_id = \$1 and
        ( ( \$2 in ( s.url, s.guid ) ) or
          ( \$3 in ( s.url, s.guid ) ) or
          ( s.title = \$4 and date_trunc( 'day', s.publish_date ) = \$5 ) )
END

    $new_story ||= clone_story( $db, $topic, $story, $dup_medium );

    merge_dup_story( $db, $topic, $story, $new_story );
}

# mark delete_medium as a dup of keep_medium and merge
# all stories from all topics in delete_medium into
# keep_medium
sub merge_dup_medium_all_topics
{
    my ( $db, $delete_medium, $keep_medium ) = @_;

    $db->query( <<END, $keep_medium->{ media_id }, $delete_medium->{ media_id } );
update media set dup_media_id = ? where media_id = ?
END

    my $stories = $db->query( <<END, $delete_medium->{ media_id } )->hashes;
SELECT distinct s.*, cs.topics_id
    FROM stories s
        join topic_stories cs on ( s.stories_id = cs.stories_id )
    WHERE
        s.media_id = ?
END

    my $topics_map = {};
    my $topics     = $db->query( "select * from topics" )->hashes;
    map { $topics_map->{ $_->{ topics_id } } = $_ } @{ $topics };

    for my $story ( @{ $stories } )
    {
        my $topic = $topics_map->{ $story->{ topics_id } };
        merge_dup_media_story( $db, $topic, $story );
    }
}

# merge all stories belonging to dup_media_id media to the dup_media_id in the current topic
sub merge_dup_media_stories
{
    my ( $db, $topic ) = @_;

    INFO( "merge dup media stories" );

    my $dup_media_stories = $db->query( <<END, $topic->{ topics_id } )->hashes;
SELECT distinct s.*
    FROM snap.live_stories s
        join topic_stories cs on ( s.stories_id = cs.stories_id and s.topics_id = cs.topics_id )
        join media m on ( s.media_id = m.media_id )
    WHERE
        m.dup_media_id is not null and
        cs.topics_id = ?
END

    INFO "merging " . scalar( @{ $dup_media_stories } ) . " stories" if ( scalar( @{ $dup_media_stories } ) );

    map { merge_dup_media_story( $db, $topic, $_ ) } @{ $dup_media_stories };
}

# import all topic_seed_urls that have not already been processed;
# return 1 if new stories were added to the topic and 0 if not
sub import_seed_urls
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
    $db->execute_with_large_work_mem(
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

# add the medium url to the topic_ignore_redirects table
sub add_medium_url_to_ignore_redirects
{
    my ( $db, $medium ) = @_;

    my $url = MediaWords::Util::URL::normalize_url_lossy( $medium->{ url } );

    my $ir = $db->query( "select * from topic_ignore_redirects where url = ?", $url )->hash;

    return if ( $ir );

    $db->create( 'topic_ignore_redirects', { url => $url } );
}

# given the completed topic_fetch_urls rows, add any fetched stories (in topic_fetch_urls.stories_id) to the topic
# if they match they topic pattern.
sub add_to_topic_stories_if_match($$$$)
{
    my ( $db, $topic, $topic_fetch_url, $iteration ) = @_;

    TRACE "add story if match: $topic_fetch_url->{ url }";

    return unless ( $topic_fetch_url->{ stories_id } );

    my $story = $db->require_by_id( 'stories', int( $topic_fetch_url->{ stories_id } ) );
    my $link = $db->find_by_id( 'topic_links', int( $topic_fetch_url->{ topic_links_id } || 0 ) );

    return if ( story_is_topic_story( $db, $topic, $story ) );

    if ( $topic_fetch_url->{ assume_match } || story_matches_topic_pattern( $db, $topic, $story ) )
    {
        TRACE "topic match: " . ( $link->{ url } || '' );

        add_to_topic_stories( $db, $topic, $story, $iteration + 1, 0 );
    }
}

# get the field pointing to the stories table from
# one of the below topic url tables
sub get_story_field_from_url_table
{
    my ( $table ) = @_;

    my $story_field;
    if ( $table eq 'topic_links' )
    {
        $story_field = 'ref_stories_id';
    }
    elsif ( $table eq 'topic_seed_urls' )
    {
        $story_field = 'stories_id';
    }
    else
    {
        LOGCONFESS( "Unknown table: '$table'" );
    }

    return $story_field;
}

# given a list of stories, keep the story with the shortest title and
# merge the other stories into that story
sub merge_dup_stories
{
    my ( $db, $topic, $stories ) = @_;

    TRACE( "merge dup stories" );

    my $stories_ids_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $story_sentence_counts = $db->query( <<END )->hashes;
select stories_id, count(*) sentence_count from story_sentences where stories_id in ($stories_ids_list) group by stories_id
END

    my $ssc = {};
    map { $ssc->{ $_->{ stories_id } } = 0 } @{ $stories };
    map { $ssc->{ $_->{ stories_id } } = $_->{ sentence_count } } @{ $story_sentence_counts };

    $stories = [ sort { $ssc->{ $b->{ stories_id } } <=> $ssc->{ $a->{ stories_id } } } @{ $stories } ];

    my $keep_story = shift( @{ $stories } );

    TRACE "duplicates: $keep_story->{ title } [$keep_story->{ url } $keep_story->{ stories_id }]";
    map { TRACE "\t$_->{ title } [$_->{ url } $_->{ stories_id }]"; } @{ $stories };

    map { merge_dup_story( $db, $topic, $_, $keep_story ) } @{ $stories };
}

# return hash of { $media_id => $stories } for the topic
sub get_topic_stories_by_medium
{
    my ( $db, $topic ) = @_;

    my $stories = $db->query( <<END, $topic->{ topics_id } )->hashes;
select s.stories_id, s.media_id, s.title, s.url, s.publish_date
    from snap.live_stories s
    where s.topics_id = ?
END

    my $media_lookup = {};
    map { push( @{ $media_lookup->{ $_->{ media_id } } }, $_ ) } @{ $stories };

    return $media_lookup;
}

# look for duplicate stories within each media source and merge any duplicates into the
# story with the shortest title
sub find_and_merge_dup_stories
{
    my ( $db, $topic ) = @_;

    INFO( "find and merge dup stories" );

    for my $get_dup_stories (
        [ 'url',   \&MediaWords::DBI::Stories::get_medium_dup_stories_by_url ],
        [ 'title', \&MediaWords::DBI::Stories::get_medium_dup_stories_by_title ]
      )
    {
        my $f_name = $get_dup_stories->[ 0 ];
        my $f      = $get_dup_stories->[ 1 ];

        # regenerate story list each time to capture previously merged stories
        my $media_lookup = get_topic_stories_by_medium( $db, $topic );

        my $num_media = scalar( keys( %{ $media_lookup } ) );
        my $i         = 0;
        while ( my ( $media_id, $stories ) = each( %{ $media_lookup } ) )
        {
            INFO( "merging dup stories: media [$i / $num_media]" ) if ( ( $i++ % 1000 ) == 0 );
            my $dup_stories = $f->( $db, $stories );
            map { merge_dup_stories( $db, $topic, $_ ) } @{ $dup_stories };
        }
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

# for the given topic, get a solr publish_date clause that will return one month of the seed query,
# starting at start_date and offset by $month_offset months.  return undef if $month_offset puts
# the start date past the topic start date.
sub get_solr_query_month_clause($$)
{
    my ( $topic, $month_offset ) = @_;

    my $topic_start = Time::Piece->strptime( $topic->{ start_date }, "%Y-%m-%d" );
    my $topic_end   = Time::Piece->strptime( $topic->{ end_date },   "%Y-%m-%d" );

    my $offset_start = $topic_start->add_months( $month_offset );
    my $offset_end   = $offset_start->add_months( 1 );

    return undef if ( $offset_start > $topic_end );

    $offset_end = $topic_end if ( $offset_end > $topic_end );

    my $solr_start = $offset_start->strftime( '%Y-%m-%d' ) . 'T00:00:00Z';
    my $solr_end   = $offset_end->strftime( '%Y-%m-%d' ) . 'T23:59:59Z';

    my $date_clause = "publish_day:[$solr_start TO $solr_end]";

    return $date_clause;
}

# get the full solr query by combining the solr_seed_query with generated clauses for start and
# end date from topics and media clauses from topics_media_map and topics_media_tags_map.
# only return a query for up to a month of the given a query, using the zero indexed $month_offset to
# fetch $month_offset to return months after the first.  return undef if the month_offset puts the
# query start date beyond the topic end date. otherwise return hash in the form of { q => query, fq => filter_query }
sub get_full_solr_query($$;$$$$)
{
    my ( $db, $topic, $media_ids, $media_tags_ids, $month_offset ) = @_;

    $month_offset ||= 0;

    my $date_clause = get_solr_query_month_clause( $topic, $month_offset );

    return undef unless ( $date_clause );

    my $solr_query = "( $topic->{ solr_seed_query } )";

    my $media_clauses = [];
    my $topics_id     = $topic->{ topics_id };

    $media_ids ||= $db->query( "select media_id from topics_media_map where topics_id = ?", $topics_id )->flat;
    if ( @{ $media_ids } )
    {
        my $media_ids_list = join( ' ', @{ $media_ids } );
        push( @{ $media_clauses }, "media_id:( $media_ids_list )" );
    }

    $media_tags_ids ||= $db->query( "select tags_id from topics_media_tags_map where topics_id = ?", $topics_id )->flat;
    if ( @{ $media_tags_ids } )
    {
        my $media_tags_ids_list = join( ' ', @{ $media_tags_ids } );
        push( @{ $media_clauses }, "tags_id_media:( $media_tags_ids_list )" );
    }

    if ( !( $topic->{ solr_seed_query } =~ /media_id\:|tags_id_media\:/ ) && !@{ $media_clauses } )
    {
        die( "query must include at least one media source or media set" );
    }

    if ( @{ $media_clauses } )
    {
        my $media_clause_list = join( ' or ', @{ $media_clauses } );
        $solr_query .= " and ( $media_clause_list )";
    }

    my $solr_params = { q => $solr_query, fq => $date_clause };

    DEBUG( "full solr query: q = $solr_query, fq = $date_clause" );

    return $solr_params;
}

# import a single month of the solr seed query.  we do this to avoid giant queries that timeout in solr.
sub import_solr_seed_query_month($$$)
{
    my ( $db, $topic, $month_offset ) = @_;

    return if ( $topic->{ ch_monitor_id } );

    my $max_stories = $topic->{ max_stories };

    # if solr maxes out on returned stories, it returns a few documents less than the rows= parameter, so we
    # assume that we hit the solr max if we are within 5% of the ma stories
    my $max_returned_stories = $max_stories * 0.95;

    my $solr_query = get_full_solr_query( $db, $topic, undef, undef, $month_offset );

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

# send high priority jobs to fetch facebook data for all stories that don't yet have it
sub fetch_social_media_data ($$)
{
    my ( $db, $topic ) = @_;

    INFO( "fetch social media data" );

    # test spider should be able to run with job broker, so we skip social media collection
    return if ( $_test_mode );

    my $cid = $topic->{ topics_id };

    do
    {
        eval { MediaWords::Job::Facebook::FetchStoryStats->add_topic_stories_to_queue( $db, $topic ); };
        ( sleep( 5 ) && INFO( 'waiting for rabbit ...' ) ) if ( error_is_amqp( $@ ) );
    } until ( !error_is_amqp( $@ ) );

    my $poll_wait = 30;
    my $retries   = int( $MAX_SOCIAL_MEDIA_FETCH_TIME / $poll_wait ) + 1;

    for my $i ( 1 .. $retries )
    {
        return if ( all_facebook_data_fetched( $db, $topic ) );
        sleep $poll_wait;
    }

    LOGCONFESS( "Timed out waiting for social media data" );
}

# move all topic stories with a foreign_rss_links medium from topic_stories back to topic_seed_urls
sub merge_foreign_rss_stories($$)
{
    my ( $db, $topic ) = @_;

    MediaWords::TM::Stories::merge_foreign_rss_stories( $db, $topic );
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
        die( "Fetch error rate of $fetch_error_rate is great than max of $MAX_JOB_ERROR_RATE" );
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
        die( "link error rate of $link_error_rate is great than max of $MAX_JOB_ERROR_RATE" );
    }
}

# mine the given topic for links and to recursively discover new stories on the web.
# options:
#   import_only - only run import_seed_urls and import_solr_seed and exit
#   skip_outgoing_foreign_rss_links - skip slow process of adding links from foreign_rss_links media
#   skip_post_processing - skip social media fetching and snapshotting
sub do_mine_topic ($$;$)
{
    my ( $db, $topic, $options ) = @_;

    # commenting this out until we deploy the story index
    # if ( !$topic->{ is_story_index_ready } )
    # {
    #     die( "refusing to run topic because is_story_index_ready is false" );
    # }

    map { $options->{ $_ } ||= 0 }
      qw/cache_broken_downloads import_only skip_outgoing_foreign_rss_links skip_post_processing test_mode/;

    # Log activity that is about to start
    MediaWords::DBI::Activities::log_system_activity( $db, 'tm_mine_topic', $topic->{ topics_id }, $options )
      || LOGCONFESS( "Unable to log the 'tm_mine_topic' activity." );

    update_topic_state( $db, $topic, "fetching tweets" );
    fetch_and_import_twitter_urls( $db, $topic );

    update_topic_state( $db, $topic, "importing solr seed query" );
    import_solr_seed_query( $db, $topic );

    # this may put entires into topic_seed_urls, so run it before import_seed_urls.
    # something is breaking trying to call this perl.  commenting out for time being since we only need
    # this when we very rarely change the foreign_rss_links field of a media source - hal
    # update_topic_state( $db, $topic, "merging foreign rss stories" );
    # merge_foreign_rss_stories( $db, $topic );

    update_topic_state( $db, $topic, "importing seed urls" );
    if ( import_seed_urls( $db, $topic ) > $MIN_SEED_IMPORT_FOR_PREDUP_STORIES )
    {
        # merge dup stories before as well as after spidering to avoid extra spidering work
        update_topic_state( $db, $topic, "merging duplicate stories" );
        find_and_merge_dup_stories( $db, $topic );
    }

    unless ( $options->{ import_only } )
    {
        update_topic_state( $db, $topic, "running spider" );
        run_spider( $db, $topic );

        check_job_error_rate( $db, $topic );

        # merge dup media and stories again to catch dups from spidering
        update_topic_state( $db, $topic, "merging duplicate media stories" );
        merge_dup_media_stories( $db, $topic );

        update_topic_state( $db, $topic, "merging duplicate stories" );
        find_and_merge_dup_stories( $db, $topic );

        update_topic_state( $db, $topic, "adding source link dates" );
        add_source_link_dates( $db, $topic );

        if ( !$options->{ skip_post_processing } )
        {
            update_topic_state( $db, $topic, "fetching social media data" );
            fetch_social_media_data( $db, $topic );

            update_topic_state( $db, $topic, "snapshotting" );
            MediaWords::TM::Snapshot::snapshot_topic( $db, $topic->{ topics_id } );
        }
    }
}

# if twitter topic corresponding to the main topic does not already exist, create it
sub find_or_create_twitter_topic($$)
{
    my ( $db, $parent_topic ) = @_;

    INFO( "find or create twitter topic" );

    my $twitter_topic = $db->query( <<SQL, $parent_topic->{ topics_id } )->hash;
select * from topics where twitter_parent_topics_id = ?
SQL

    return $twitter_topic if ( $twitter_topic );

    my $topic_tag_set = $db->create( 'tag_sets', { name => "topic $parent_topic->{ name } (twitter)" } );

    $twitter_topic = {
        twitter_parent_topics_id => $parent_topic->{ topics_id },
        name                     => "$parent_topic->{ name } (twitter)",
        pattern                  => '(none)',
        solr_seed_query          => '(none)',
        solr_seed_query_run      => 't',
        description              => "twitter child topic of $parent_topic->{ name }",
        topic_tag_sets_id        => $topic_tag_set->{ topic_tag_sets_id },
        ch_monitor_id            => $parent_topic->{ ch_monitor_id }
    };

    my $topic = $db->create( 'topics', $twitter_topic );

    my $parent_topic_dates =
      $db->query( "select * from topics_with_dates where topics_id = ?", $parent_topic->{ topics_id } )->hash;

    $db->query( <<SQL, $topic->{ topics_id }, $parent_topic->{ topics_id } );
insert into topic_dates ( topics_id, boundary, start_date, end_date )
    select \$1, true, start_date::date, end_date::date from topics_with_dates where topics_id = \$2
SQL

    return $topic;
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

    # now insert any topic_tweet_urls that are not already in the topic_seed_urls
    $db->execute_with_large_work_mem(
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
SQL
        $topic->{ topics_id }
    );
}

# if there is a ch_monitor_id for the given topic, fetch the twitter data from crimson hexagon and twitter
sub fetch_and_import_twitter_urls($$)
{
    my ( $db, $topic ) = @_;

    # only add  twitter data if there is a ch_monitor_id
    return unless ( $topic->{ ch_monitor_id } );

    MediaWords::TM::FetchTopicTweets::fetch_topic_tweets( $db, $topic->{ topics_id } );

    seed_topic_with_tweet_urls( $db, $topic );
}

# wrap do_mine_topic in eval and handle errors and state1
sub mine_topic ($$;$)
{
    my ( $db, $topic, $options ) = @_;

    my $prev_test_mode = $_test_mode;

    init_static_variables();

    $_test_mode = 1 if ( $options->{ test_mode } );

    if ( $topic->{ state } ne 'running' )
    {
        MediaWords::TM::send_topic_alert( $db, $topic, "started topic spidering" );
    }

    eval {
        do_mine_topic( $db, $topic );
        MediaWords::TM::send_topic_alert( $db, $topic, "successfully completed topic spidering" );
    };
    if ( $@ )
    {
        my $error = $@;
        MediaWords::TM::send_topic_alert( $db, $topic, "aborted topic spidering due to error" );
        LOGDIE( $error );
    }

    $_test_mode = $prev_test_mode;
}

1;
