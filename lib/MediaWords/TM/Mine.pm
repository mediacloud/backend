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

use Carp::Always;
use Data::Dumper;
use DateTime;
use Digest::MD5;
use Encode;
use Getopt::Long;
use HTML::Entities;
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
use MediaWords::TM::GuessDate;
use MediaWords::TM::GuessDate::Result;
use MediaWords::TM::Snapshot;
use MediaWords::DB;
use MediaWords::DBI::Activities;
use MediaWords::DBI::Media;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::GuessDate;
use MediaWords::Job::Bitly::FetchStoryStats;
use MediaWords::Job::ExtractAndVector;
use MediaWords::Job::Facebook::FetchStoryStats;
use MediaWords::Job::TM::ExtractStoryLinks;
use MediaCloud::JobManager::Job;
use MediaWords::Languages::Language;
use MediaWords::Solr;
use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::Util::IdentifyLanguage;
use MediaWords::Util::SQL;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;
use MediaWords::Util::Web;
use MediaWords::Util::Web::Cache;
use MediaWords::Util::Bitly;

# max number of solely self linked stories to include
Readonly my $MAX_SELF_LINKED_STORIES => 100;

# total time to wait for fetching of social media metrics
Readonly my $MAX_SOCIAL_MEDIA_FETCH_TIME => ( 60 * 60 * 24 );

# max prooprtion of stories with no bitly metrics
Readonly my $MAX_NULL_BITLY_STORIES => 0.02;

# add new links in chunks of this size
Readonly my $ADD_NEW_LINKS_CHUNK_SIZE => 1000;

# if mine_topic is run with the test_mode option, set this true and do not try to queue extractions
my $_test_mode;

# ignore links that match this pattern
my $_ignore_link_pattern =
  '(www.addtoany.com)|(novostimira.com)|(ads\.pheedo)|(www.dailykos.com\/user)|' .
  '(livejournal.com\/(tag|profile))|(sfbayview.com\/tag)|(absoluteastronomy.com)|' .
  '(\/share.*http)|(digg.com\/submit)|(facebook.com.*mediacontentsharebutton)|' .
  '(feeds.wordpress.com\/.*\/go)|(sharetodiaspora.github.io\/)|(iconosquare.com)|' .
  '(unz.com)|(answers.com)|(downwithtyranny.com\/search)|(scoop\.?it)|(sco\.lt)|' .
  '(pronk.*\.wordpress\.com\/(tag|category))|(wn\.com)|(pinterest\.com\/pin\/create)|(feedblitz\.com)|' . '(atomz.com)';

# cache of media by media id
my $_media_cache = {};

# cache for spidered:spidered tag
my $_spidered_tag;

# cache of media by sanitized url
my $_media_url_lookup;

# lookup of self linked domains, for efficient skipping before adding a story
my $_skip_self_linked_domain = {};

# cache that indicates whether we should recheck a given url
my $_no_potential_match_urls = {};

my $_link_extractor;

# initialize static variables for each run
sub init_static_variables
{
    $_media_cache             = {};
    $_spidered_tag            = undef;
    $_media_url_lookup        = undef;
    $_skip_self_linked_domain = {};
    $_no_potential_match_urls = {};
}

# update topics.state in the database
sub update_topic_state($$$;$)
{
    my ( $db, $topic, $message ) = @_;

    eval { MediaWords::Job::TM::MineTopic->update_job_state_message( $db, $message ) };
    if ( $@ )
    {
        die( "error updating job state (mine_topic() must be called from MediaWords::Job::TM::MineTopic): $@" );
    }
}

# fetch each link and add a { redirect_url } field if the { url } field redirects to another url
sub add_redirect_links
{
    my ( $db, $stories ) = @_;

    my $urls         = [];
    my $story_lookup = {};

    for my $story ( @{ $stories } )
    {
        my $story_url = URI->new( $story->{ url } )->as_string;

        unless ( MediaWords::Util::URL::is_http_url( $story_url ) )
        {
            WARN "Story URL $story_url is not HTTP(s) URL";
            next;
        }

        push( @{ $urls }, $story_url );
        $story_lookup->{ $story_url } = $story;
    }

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $urls );

    for my $response ( @{ $responses } )
    {
        my $original_url = $response->original_request->url;
        my $final_url    = $response->request->url;
        if ( $story_lookup->{ $original_url } )
        {
            $story_lookup->{ $original_url }->{ redirect_url } = $final_url;
        }
        else
        {
            WARN "Original URL $original_url was not found in story lookup hash";
        }
    }
}

sub get_cached_medium_by_id
{
    my ( $db, $media_id ) = @_;

    if ( my $medium = $_media_cache->{ $media_id } )
    {
        TRACE "MEDIA CACHE HIT";
        return $medium;
    }

    TRACE "MEDIA CACHE MISS";
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

    my $content_ref;
    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };
    if ( $@ )
    {
        MediaWords::DBI::Stories::fix_story_downloads_if_needed( $db, $story );
        $download = $db->find_by_id( 'downloads', int( $download->{ downloads_id } ) );
        eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };
        WARN "Error refetching content: $@" if ( $@ );
    }

    return $content_ref ? $$content_ref : '';
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

    INFO "GENERATE TOPIC LINKS: " . scalar( @{ $stories } );

    my $topic_links = [];

    if ( $topic->{ ch_monitor_id } )
    {
        INFO( "SKIP LINK GENERATION FOR TWITTER TOPIC" );
        return;
    }

    my $stories_ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    $db->query( <<SQL, $topic->{ topics_id } );
update topic_stories set link_mined = 'f' where stories_id in ( select id from $stories_ids_table ) and topics_id = ?
SQL

    my $queued_stories_ids = [];
    for my $story ( @{ $stories } )
    {
        next unless ( story_within_topic_date_range( $db, $topic, $story ) );

        push( @{ $queued_stories_ids }, $story->{ stories_id } );

        MediaWords::Job::TM::ExtractStoryLinks->add_to_queue(
            { stories_id => $story->{ stories_id }, topics_id => $topic->{ topics_id } } );

        INFO( "queued link extraction for story $story->{ title } $story->{ url }." );
    }

    INFO( "waiting for link extraction jobs to finish" );

    my $queued_ids_table = $db->get_temporary_ids_table( $queued_stories_ids );

    # poll every $sleep_time seconds waiting for the jobs to complete.  die if the number of stories left to process
    # has not shrunk for $large_timeout seconds.  warn but continue if the number of stories left to process
    # is only 5% of the total and short_timeout has passed (this is to make the topic not hang entirely because
    # of one link extractor job error).
    my $prev_num_queued_stories = scalar( @{ $stories } );
    my $last_change_time        = time();
    my $sleep_time              = 5;
    my $long_timeout            = 60 * 60;
    my $short_timeout           = 15;
    my $max_errored_stories     = scalar( @{ $stories } ) / 20;
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
        if ( ( time() - $last_change_time ) > $long_timeout )
        {
            LOGDIE( "Timed out waiting for story link extraction." );
        }

        if ( ( ( time() - $last_change_time ) > $short_timeout ) && ( $num_queued_stories < $max_errored_stories ) )
        {
            WARN( "Continuing after short timeout with $num_queued_stories remaining in link extraction pool" );
            last;
        }

        INFO( "$num_queued_stories stories left in link extraction pool...." );

        $prev_num_queued_stories = $num_queued_stories;
        sleep( $sleep_time );
    }

    # cleanup any out of date range or errored stories
    $db->query( <<SQL, $topic->{ topics_id } );
update topic_stories set link_mined = 't'
    where
        stories_id in ( select id from $queued_ids_table ) and
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

# lookup medium by a sanitized url.  For media with dup_media_id set, return the
# dup_media_id medium rather than the medium itself.
sub lookup_medium_by_url
{
    my ( $db, $url ) = @_;

    if ( !$_media_url_lookup->{ MediaWords::Util::URL::normalize_url_lossy( $url ) } )
    {
        my $max_media_id = 0;
        if ( $_media_url_lookup )
        {
            $max_media_id = List::Util::max( map( { $_->{ media_id } } values( %{ $_media_url_lookup } ) ) );
        }
        my $media =
          $db->query( "select * from media where foreign_rss_links = false and media_id > ?", $max_media_id )->hashes;
        for my $medium ( @{ $media } )
        {
            my $dup_medium = get_dup_medium( $db, $medium->{ media_id } );

            $medium = $dup_medium ? $dup_medium : $medium;

            LOGCROAK( "foreign rss medium $medium->{ media_id }" ) if ( $medium->{ foreign_rss_links } );
            $_media_url_lookup->{ MediaWords::Util::URL::normalize_url_lossy( $medium->{ url } ) } = $medium;
        }
    }

    return $_media_url_lookup->{ MediaWords::Util::URL::normalize_url_lossy( $url ) };
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

# make sure that the medium_name is unique so that we can insert it without causing an unique key error
sub get_unique_medium_name
{
    my ( $db, $name, $i ) = @_;

    $name = substr( $name, 0, 124 );

    my $q_name = $i ? "$name $i" : $name;

    my $name_exists = $db->query( "select 1 from media where name = ?", $q_name )->hash;

    if ( $name_exists )
    {
        return get_unique_medium_name( $db, $name, ++$i );
    }
    else
    {
        return $q_name;
    }
}

# make sure that the url is unique so that we can insert it without causing an unique key error
sub get_unique_medium_url
{
    my ( $db, $url, $i ) = @_;

    $url = substr( $url, 0, 1000 );

    my $q_url;
    if ( !$i )
    {
        $q_url = $url;
    }
    elsif ( $i == 1 )
    {
        $q_url = "$url#spider";
    }
    else
    {
        $q_url = "$url#spider$i";
    }

    my $url_exists = $db->query( "select 1 from media where url = ?", $q_url )->hash;

    if ( $url_exists )
    {
        return get_unique_medium_url( $db, $url, ++$i );
    }
    else
    {
        return $q_url;
    }
}

# return a spider specific media_id for each story.  create a new spider specific medium
# based on the domain of the story url
sub get_spider_medium
{
    my ( $db, $story_url ) = @_;

    my ( $medium_url, $medium_name ) = generate_medium_url_and_name_from_url( $story_url );

    my $medium = lookup_medium_by_url( $db, $medium_url );

    $medium ||= $db->query( <<END, $medium_name )->hash;
select m.* from media m
    where lower( m.name ) = lower( ? ) and m.foreign_rss_links = false
END

    $medium ||= lookup_medium_by_url( $db, "${ medium_url }#spider" );

    $medium = get_dup_medium( $db, $medium->{ dup_media_id } ) if ( $medium && $medium->{ dup_media_id } );

    return $medium if ( $medium );

    # avoid conflicts with existing media names and urls that are missed
    # by the above query b/c of dups feeds or foreign_rss_links
    $medium_name = get_unique_medium_name( $db, $medium_name );
    $medium_url = get_unique_medium_url( $db, $medium_url );

    $medium = {
        name      => $medium_name,
        url       => $medium_url,
        moderated => 't',
    };

    $medium = $db->create( 'media', $medium );

    INFO "add medium: $medium_name / $medium_url / $medium->{ media_id }";

    my $spidered_tag = get_spidered_tag( $db );

    $db->create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $spidered_tag->{ tags_id } } );

    add_medium_to_url_lookup( $medium );

    return $medium;
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
        "insert into feeds ( media_id, url, name, feed_status ) " . "  values ( ?, ?, 'Spider Feed', 'inactive' )",
        $medium->{ media_id },
        $medium->{ url }
    );

    return $db->query( $feed_query, $medium->{ media_id }, $medium->{ url } )->hash;
}

# extract the story for the given download
sub extract_download($$$)
{
    my ( $db, $download, $story ) = @_;

    return if ( $download->{ url } =~ /jpg|pdf|doc|mp3|mp4|zip$/i );

    return if ( $download->{ url } =~ /livejournal.com\/(tag|profile)/i );

    my $dt = $db->query( "select 1 from download_texts where downloads_id = ?", $download->{ downloads_id } )->hash;
    return if ( $dt );

    my $extractor_args = MediaWords::DBI::Stories::ExtractorArguments->new(
        {
            no_dedup_sentences => 0,
            use_cache          => 1,
        }
    );

    eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, $extractor_args ); };

    if ( my $error = $@ )
    {
        WARN "extract error processing download $download->{ downloads_id }: $error";
    }
}

# get a date for a new story by trying each of the following, in this order:
# * assigning a date from the merged old story,
# * guessing the date using MediaWords::TM::GuessDate,
# * assigning the date of the source link, or
# * assigning the current date
sub get_new_story_date
{
    my ( $db, $story, $story_content, $old_story, $source_link ) = @_;

    # for merged stories, use the method associated with the old story
    # or use 'merged_story_rss' to indicate that we got the date from a
    # a merged story whose date came from rss
    if ( $old_story && $old_story->{ publish_date } )
    {
        my ( $old_story_method ) = $db->query( <<END, $old_story->{ stories_id } )->flat;
select t.tag from tags t, tag_sets ts, stories_tags_map stm
    where stm.stories_id = ? and stm.tags_id = t.tags_id and
        t.tag_sets_id = ts.tag_sets_id and ts.name = 'date_guess_method'
END
        $old_story_method ||= 'merged_story_rss';

        return ( $old_story_method, $old_story->{ publish_date } );
    }

    # otherwise, if there's a publish_date in the link hash, use that
    elsif ( $source_link->{ publish_date } )
    {
        return ( 'manual', $source_link->{ publish_date } );
    }

    my $source_story;
    if ( $source_link && $source_link->{ stories_id } )
    {
        $source_story = $db->find_by_id( 'stories', int( $source_link->{ stories_id } ) );
        $story->{ publish_date } = $source_story->{ publish_date };
    }

    my $date = MediaWords::TM::GuessDate::guess_date( $story->{ url }, $story_content );
    if ( $date->{ result } eq $MediaWords::TM::GuessDate::Result::FOUND )
    {
        return ( $date->{ guess_method }, $date->{ date } );
    }
    elsif ( $date->{ result } eq $MediaWords::TM::GuessDate::Result::NOT_FOUND )
    {
        if ( $source_story )
        {
            return ( 'publish_date', $source_story->{ publish_date } );
        }
        else
        {
            return ( 'current_time', MediaWords::Util::SQL::sql_now() );
        }
    }
    else
    {
        die "MediaWords::TM::GuessDate::Result value is unknown.";
    }
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

# generate a new story hash from the story content, an existing story, a link, and a medium.
# includes guessing the publish date.  return the story and the date guess method
sub generate_new_story_hash
{
    my ( $db, $story_content, $old_story, $link, $medium ) = @_;

    my $story = {
        url          => $old_story->{ url },
        guid         => $link->{ guid } || $old_story->{ url },
        media_id     => $medium->{ media_id },
        collect_date => MediaWords::Util::SQL::sql_now,
        title        => $old_story->{ title },
        publish_date => $link->{ publish_date },
        description  => ''
    };

    # postgres refuses to insert text values with the null character
    for my $field ( qw/url guid title/ )
    {
        $story->{ $field } =~ s/\x00//g;
    }

    if ( $link->{ publish_date } )
    {
        return ( $story, 'manual' );
    }
    else
    {
        my ( $date_guess_method, $publish_date ) = get_new_story_date( $db, $story, $story_content, $old_story, $link );

        TRACE "date guess: $date_guess_method: $publish_date";

        $story->{ publish_date } = $publish_date;
        return ( $story, $date_guess_method );
    }
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

# save the link in a list of dead links
sub log_dead_link
{
    my ( $db, $link ) = @_;

    my $dead_link = {
        topics_id  => $link->{ topics_id },
        stories_id => $link->{ stories_id },
        url        => $link->{ url }
    };

    eval { $db->create( 'topic_dead_links', $dead_link ); };
    if ( $@ )
    {
        my $error_message = $@;

        # MC_REWRITE_TO_PYTHON:
        #
        # Some calls to create() fail with:
        #
        #      UnicodeEncodeError: 'utf-8' codec can't encode character '\udf33' in position 26352: surrogates not allowed
        #
        # for insert hash:
        #
        #     {
        #         'stories_id' => 629277868,
        #         'url' => 'http://www.thatssomichelle.com/2011/11/pumpkin-mac-and-cheese.html',
        #         'topics_id' => 2030,
        #     }
        #
        # I wish I knew what's causing this, but I don't. Unable to reproduce
        # either -- calling create() with a failing hash in an isolated script
        # works fine, so maybe it's related to the caller somehow? No idea.
        #
        # So here we silently ignore one-off UnicodeEncodeError exceptions
        # because "topic_dead_links" table is used for statistics, and it's not
        # a big deal if some links fail at create() here.
        #
        # One should try removing this exception after this code gets rewritten
        # to Python because it might be related to Inline::Python's memory
        # management or exception handling.
        if ( $error_message =~ /UnicodeEncodeError.+?surrogates not allowed/ )
        {
            WARN "Non-critical UnicodeEncodeError while trying to INSERT " .
              Dumper( $dead_link ) . " into 'topic_dead_links': $error_message";
        }
        else
        {
            # die() on all other exceptions
            LOGCONFESS "Failed INSERTing into 'topic_dead_links': $error_message";
        }
    }
}

# send story to the extraction queue in the hope that it will already be extracted by the time we get to the extraction
# step later in add_new_links_chunk process.
sub queue_extraction($$)
{
    my ( $db, $story ) = @_;

    return if ( $_test_mode );

    my $args = {
        stories_id            => $story->{ stories_id },
        skip_bitly_processing => 1,
        use_cache             => 1
    };

    my $priority = $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_HIGH;
    eval { MediaWords::Job::ExtractAndVector->add_to_queue( $args, $priority ) };
    ERROR( "error queueing extraction: $@" ) if ( $@ );
}

# add a new story and download corresponding to the given link or existing story
sub add_new_story
{
    my ( $db, $link, $old_story, $topic, $allow_foreign_rss_links, $check_pattern, $skip_extraction ) = @_;

    LOGCONFESS( "only one of $link or $old_story should be set" ) if ( $link && $old_story );

    my $story_content;
    if ( $link && $link->{ content } )
    {
        $story_content = $link->{ content };
        $link->{ redirect_url } ||= $link->{ url };
        $link->{ title }        ||= $link->{ url };
        $old_story->{ url }     ||= $link->{ url };
        $old_story->{ title }   ||= $link->{ title };
    }
    elsif ( $link )
    {
        $story_content = MediaWords::Util::Web::Cache::get_cached_link_download( $link );

        if ( !$story_content )
        {
            log_dead_link( $db, $link );
            DEBUG( "SKIP - NO CONTENT" );
            return;
        }

        $link->{ redirect_url } ||= MediaWords::Util::Web::Cache::get_cached_link_download_redirect_url( $link );

        if ( ignore_redirect( $db, $link ) )
        {
            $old_story->{ title } = "dead link: $link->{ url }";
            $old_story->{ url }   = $link->{ url };
            $story_content        = '';
        }
        else
        {
            $old_story->{ url } = $link->{ redirect_url } || $link->{ url };
            $old_story->{ title } =
              $link->{ title } || MediaWords::Util::HTML::html_title( $story_content, $old_story->{ url }, 1024 );
        }
    }
    else
    {
        # make sure content exists in case content is missing from the existing story
        MediaWords::DBI::Stories::fix_story_downloads_if_needed( $db, $old_story );
        $story_content = ${ MediaWords::DBI::Stories::fetch_content( $db, $old_story ) };
    }

    TRACE "add_new_story: $old_story->{ url }";

    # if neither the url nor the content match the pattern, it cannot be a match so return and don't add the story
    if (  !$link->{ assume_match }
        && $check_pattern
        && !potential_story_matches_topic_pattern( $db, $topic, $link->{ url }, $link->{ redirect_url }, $story_content ) )
    {
        TRACE "SKIP - NO POTENTIAL MATCH";
        return;
    }

    $old_story->{ url } = substr( $old_story->{ url }, 0, 1024 );

    my $medium = get_dup_medium( $db, $old_story->{ media_id }, $allow_foreign_rss_links )
      || get_spider_medium( $db, $old_story->{ url } );
    my $feed = get_spider_feed( $db, $medium );

    my $spidered_tag = get_spidered_tag( $db );

    my ( $story, $date_guess_method ) = generate_new_story_hash( $db, $story_content, $old_story, $link, $medium );

    $story = safely_create_story( $db, $story );

    $db->create( 'stories_tags_map', { stories_id => $story->{ stories_id }, tags_id => $spidered_tag->{ tags_id } } );

    MediaWords::DBI::Stories::GuessDate::assign_date_guess_method( $db, $story, $date_guess_method, 1 );

    DEBUG( "add story: $story->{ title } / $story->{ url } / $story->{ publish_date } / $story->{ stories_id }" );

    $db->create( 'feeds_stories_map', { feeds_id => $feed->{ feeds_id }, stories_id => $story->{ stories_id } } );

    my $download = create_download_for_new_story( $db, $story, $feed );

    $download = MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );

    $skip_extraction ? queue_extraction( $db, $story ) : extract_download( $db, $download, $story );

    return $story;
}

# remove the given story from the given topic
sub remove_story_from_topic($$$)
{
    my ( $db, $stories_id, $topics_id ) = @_;

    $db->query(
        <<EOF,
        DELETE FROM topic_stories
        WHERE stories_id = ?
          AND topics_id = ?
EOF
        $stories_id, $topics_id
    );
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

# test whether the url or content of a potential story matches the topic pattern
sub potential_story_matches_topic_pattern
{
    my ( $db, $topic, $url, $redirect_url, $content ) = @_;

    my $re = $topic->{ pattern };

    my $match = ( postgres_regex_match( $db, [ $redirect_url ], $re ) || postgres_regex_match( $db, [ $url ], $re ) );

    return 1 if $match;

    my $text_content = MediaWords::Util::HTML::html_strip( $content, 1 );

    my $story_lang = MediaWords::Util::IdentifyLanguage::language_code_for_text( $text_content );

    # only match first MB of text to avoid running giant, usually binary, strings through the regex match
    $text_content = substr( $text_content, 0, 1024 * 1024 ) if ( length( $text_content ) > 1024 * 1024 );
    my $sentences = _get_sentences_from_story_text( $text_content, $story_lang );

    # shockingly, this is much faster than native perl regexes for the kind of complex, boolean-converted
    # regexes we often use for topics
    $match = postgres_regex_match( $db, $sentences, $re );

    if ( !$match )
    {
        $_no_potential_match_urls->{ $url }          = 1;
        $_no_potential_match_urls->{ $redirect_url } = 1;
    }

    return $match;
}

# return true if this url already failed a potential match, so we don't have to download it again
sub url_failed_potential_match
{
    my ( $url ) = @_;

    return $url && $_no_potential_match_urls->{ $url };
}

# return the type of match if the story title, url, description, or sentences match topic search pattern.
# return undef if no match is found.
sub story_matches_topic_pattern
{
    my ( $db, $topic, $story, $metadata_only ) = @_;

    return 'sentence' if ( !$metadata_only && ( story_sentence_matches_pattern( $db, $story, $topic ) ) );

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

# look for a story matching the link stories_id, url,  in the db
sub get_matching_story_from_db ($$;$)
{
    my ( $db, $link, $extract_policy ) = @_;

    my $u = substr( $link->{ url }, 0, 1024 );

    my $ru = '';
    if ( !ignore_redirect( $db, $link ) )
    {
        $ru = $link->{ redirect_url } ? substr( $link->{ redirect_url }, 0, 1024 ) : $u;
    }

    my $nu  = MediaWords::Util::URL::normalize_url_lossy( $u );
    my $nru = MediaWords::Util::URL::normalize_url_lossy( $ru );

    my $url_lookup = {};
    map { $url_lookup->{ $_ } = 1 } ( $u, $ru, $nu, $nru );
    my $quoted_url_list = join( ',', map { "(" . $db->quote( $_ ) . ")" } keys( %{ $url_lookup } ) );

    # TODO - only query stories_id and media_id initially

    # look for matching stories, ignore those in foreign_rss_links media
    my $stories = $db->query( <<END )->hashes;
select distinct( s.* ) from stories s
        join media m on s.media_id = m.media_id
    where ( s.url = any( array( values $quoted_url_list ) ) or s.guid = any( array( values $quoted_url_list ) ) ) and
        m.foreign_rss_links = false

union

select distinct( s.* ) from stories s
        join media m on s.media_id = m.media_id
        join topic_seed_urls csu on s.stories_id = csu.stories_id
    where ( csu.url  = any( array( values $quoted_url_list ) ) ) and
        m.foreign_rss_links = false
END

    my $story = get_preferred_story( $db, $u, $ru, $stories );

    if ( $story )
    {
        $extract_policy ||= 'extract';
        if ( $extract_policy eq 'defer' )
        {
            return $story;
        }
        elsif ( $extract_policy eq 'extract' )
        {
            my $downloads =
              $db->query( "select * from downloads where stories_id = ? and extracted = 'f' order by downloads_id",
                $story->{ stories_id } )->hashes;
            map { extract_download( $db, $_, $story ) } @{ $downloads };
        }
        else
        {
            LOGCONFESS( "Unknown extract_policy: '$extract_policy'" );
        }
    }

    return $story;
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

    INFO "EXISTING TOPIC STORY: $story->{ url }" if ( $is_old );

    return $is_old;
}

# get the redirect url for the link, add it to the hash, and save it in the db
sub add_redirect_url_to_link
{
    my ( $db, $link ) = @_;

    $link->{ redirect_url } = MediaWords::Util::Web::Cache::get_cached_link_download_redirect_url( $link );

    $db->query(
        "update topic_links set redirect_url = ? where topic_links_id = ?",
        $link->{ redirect_url },
        $link->{ topic_links_id }
    );
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

# return true if this story is already a topic story or
# if the story should be skipped for being a self linked story (see skip_self_linked_story())
sub skip_topic_story
{
    my ( $db, $topic, $story, $link ) = @_;

    return 1 if ( story_is_topic_story( $db, $topic, $story ) );

    my $spidered_tag = get_spidered_tag( $db );

    # never do a self linked story skip for stories that were not spidered
    return 0 unless ( $db->query( <<END, $story->{ stories_id }, $spidered_tag->{ tags_id } )->hash );
select 1 from stories_tags_map where stories_id = ? and tags_id = ?
END

    # don't skip if the media_id of the link source is different that the media_id of the link target
    if ( $link->{ stories_id } )
    {
        my $ss = $db->find_by_id( 'stories', int( $link->{ stories_id } ) );
        return 0 if ( $ss->{ media_id } && ( $ss->{ media_id } != $story->{ media_id } ) );
    }

    return 1 if ( _skip_self_linked_domain( $db, $link ) );

    my $cid = $topic->{ topics_id };

    # these queries can be very slow, so we only try them every once in a while randomly. if they hit true
    # once the result gets cached.  it's okay to get up to 1000 too many stories from one source -- we're just
    # trying to make sure we don't get many thousands of stories from the same source
    return 0 if ( rand( 1000 ) > 1 );

    my ( $num_stories ) = $db->query( <<END, $cid, $story->{ media_id }, $spidered_tag->{ tags_id } )->flat;
select count(*)
    from snap.live_stories s
        join stories_tags_map stm on ( s.stories_id = stm.stories_id )
    where
        s.topics_id = ? and
        s.media_id = ? and
        stm.tags_id = ?
END

    return 0 if ( $num_stories <= $MAX_SELF_LINKED_STORIES );

    my ( $num_cross_linked_stories ) = $db->query( <<END, $cid, $story->{ media_id }, $spidered_tag->{ tags_id } )->flat;
select count( distinct rs.stories_id )
    from snap.live_stories rs
        join topic_links cl on ( cl.topics_id = \$1 and rs.stories_id = cl.ref_stories_id )
        join snap.live_stories ss on ( ss.topics_id = \$1 and cl.stories_id = ss.stories_id )
        join stories_tags_map sstm on ( sstm.stories_id = ss.stories_id )
        join stories_tags_map rstm on ( rstm.stories_id = rs.stories_id )
    where
        rs.topics_id = \$1 and
        rs.media_id = \$2 and
        ss.media_id <> rs.media_id and
        sstm.tags_id = \$3 and
        rstm.tags_id = \$3
    limit ( $num_stories - $MAX_SELF_LINKED_STORIES )
END

    my ( $num_unlinked_stories ) = $db->query( <<END, $cid, $story->{ media_id } )->flat;
select count( distinct rs.stories_id )
from snap.live_stories rs
    left join topic_links cl on ( cl.topics_id = \$1 and rs.stories_id = cl.ref_stories_id )
where
    rs.topics_id = \$1 and
    rs.media_id = \$2 and
    cl.ref_stories_id is null
limit ( $num_stories - $MAX_SELF_LINKED_STORIES )
END

    my $num_self_linked_stories = $num_stories - $num_cross_linked_stories - $num_unlinked_stories;

    if ( $num_self_linked_stories > $MAX_SELF_LINKED_STORIES )
    {
        INFO "SKIP SELF LINKED STORY: $story->{ url } [$num_self_linked_stories]";

        my $medium_domain = MediaWords::Util::URL::get_url_distinctive_domain( $link->{ url } );
        $_skip_self_linked_domain->{ $medium_domain } = 1;

        return 1;
    }

    return 0;
}

# return true if the domain of the linked url is the same
# as the domain of the linking story and either the domain is in
# $_skip_self_linked_domain or the linked url is a /tag or /category page
sub _skip_self_linked_domain
{
    my ( $db, $link ) = @_;

    my $domain = MediaWords::Util::URL::get_url_distinctive_domain( $link->{ url } );

    return 0 unless ( $_skip_self_linked_domain->{ $domain } || ( $link->{ url } =~ /\/(tag|category|author|search)/ ) );

    return 0 unless ( $link->{ stories_id } );

    # only skip if the media source of the linking story is the same as the media source of the linked story.  we can't
    # know the media source of the linked story without adding it first, though, which we want to skip because it's time
    # expensive to do so.  so we just compare the url domain as a proxy for media source instead.
    my $source_story = $db->find_by_id( 'stories', int( $link->{ stories_id } ) );

    my $source_domain = MediaWords::Util::URL::get_url_distinctive_domain( $source_story->{ url } );

    if ( $source_domain eq $domain )
    {
        INFO "SKIP SELF LINKED DOMAIN: $domain";
        return 1;
    }

    return 0;
}

# check whether each link has a matching story already in db.  if so, add that story to the topic if it matches,
# otherwise add the link to the list of links to fetch.  return the list of links to fetch.
sub add_links_with_matching_stories
{
    my ( $db, $topic, $new_links ) = @_;

    my $fetch_links     = [];
    my $extract_stories = [];
    my $total_links     = scalar( @{ $new_links } );
    my $i               = 0;

    # find all the links that we can find existing stories for without having to fetch anything
    for my $link ( @{ $new_links } )
    {
        $i++;
        TRACE "spidering [$i/$total_links] $link->{ url } ...";

        next if ( $link->{ ref_stories_id } );

        next if ( _skip_self_linked_domain( $db, $link ) );

        if ( my $story = get_matching_story_from_db( $db, $link, 'defer' ) )
        {
            push( @{ $extract_stories }, $story );
            $link->{ story } = $story;
            $story->{ link } = $link;

            # we probably don't need the extraction here, but this will cache the content download, which will make
            # the link mining below much faster
            queue_extraction( $db, $story );
        }
        else
        {
            TRACE "add to fetch list ...";
            push( @{ $fetch_links }, $link );
        }
    }

    extract_stories( $db, $extract_stories );

    map { add_to_topic_stories_if_match( $db, $topic, $_, $_->{ link } ) } @{ $extract_stories };

    return $fetch_links;
}

# given the list of links, add any stories that might match the topic (by matching against url
# and raw html) and return that list of stories, none of which have been extracted
sub get_stories_to_extract
{
    my ( $db, $topic, $fetch_links ) = @_;

    MediaWords::Util::Web::Cache::cache_link_downloads( $fetch_links );

    my $extract_stories = [];

    for my $link ( @{ $fetch_links } )
    {
        next if ( $link->{ ref_stories_id } );

        TRACE "fetch spidering $link->{ url } ...";

        next if ( _skip_self_linked_domain( $db, $link ) );

        add_redirect_url_to_link( $db, $link );
        my $story = get_matching_story_from_db( $db, $link, 'defer' );

        INFO( "FOUND MATCHING STORY" ) if ( $story );

        $story ||= add_new_story( $db, $link, undef, $topic, 0, 1, 1 );

        if ( $story )
        {
            $link->{ story } = $story;
            $story->{ link } = $link;
            push( @{ $extract_stories }, $story );
        }

        $db->commit if ( $db->in_transaction() );
    }

    return $extract_stories;

}

# return the stories from the list that have no download texts associated with them.  attach
# a download to each story
sub filter_and_attach_downloads_to_extract_stories($$)
{
    my ( $db, $stories ) = @_;

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

# extract the stories
sub extract_stories
{
    my ( $db, $stories ) = @_;

    INFO "POSSIBLE EXTRACT STORIES: " . scalar( @{ $stories } );

    $stories = filter_and_attach_downloads_to_extract_stories( $db, $stories );

    INFO "EXTRACT STORIES: " . scalar( @{ $stories } );

    for my $story ( @{ $stories } )
    {
        TRACE "EXTRACT STORY: " . $story->{ url };
        extract_download( $db, $story->{ download }, $story );
    }
}

# download any unmatched link in new_links, add it as a story, extract it, add any links to the topic_links list.
# each hash within new_links can either be a topic_links hash or simply a hash with a { url } field.  if
# the link is a topic_links hash, the topic_link will be updated in the database to point ref_stories_id
# to the new link story.  For each link, set the { story } field to the story found or created for the link.
sub add_new_links_chunk($$$$)
{
    my ( $db, $topic, $iteration, $new_links ) = @_;

    my $trimmed_links = [];
    for my $link ( @{ $new_links } )
    {
        my $skip_link = url_failed_potential_match( $link->{ url } )
          || url_failed_potential_match( $link->{ redirect_url } );
        if ( $skip_link )
        {
            TRACE "ALREADY SKIPPED LINK: $link->{ url }";
        }
        else
        {
            push( @{ $trimmed_links }, $link );
        }
    }

    my $fetch_links = add_links_with_matching_stories( $db, $topic, $trimmed_links );

    my $extract_stories = get_stories_to_extract( $db, $topic, $fetch_links );

    extract_stories( $db, $extract_stories );

    map { add_to_topic_stories_if_match( $db, $topic, $_, $_->{ link } ) } @{ $extract_stories };

    $db->begin;
    for my $link ( @{ $new_links } )
    {
        $db->query( <<END, $link->{ topic_links_id } ) if ( $link->{ topic_links_id } );
delete from topic_links where topic_links_id = ? and ref_stories_id is null
END
    }
    $db->commit;
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

    return unless ( @{ $new_links } );

    # randomly shuffle the links because it is better for downloading (which has per medium throttling) and extraction
    # (which has per medium locking) to distribute urls from the same media source randomly among the list of links. the
    # link mining and solr seeding routines that feed most links to this function tend to naturally group links
    # from the same media source together.
    my $shuffled_links = [ List::Util::shuffle( @{ $new_links } ) ];

    for ( my $i = 0 ; $i < scalar( @{ $shuffled_links } ) ; $i += $ADD_NEW_LINKS_CHUNK_SIZE )
    {
        my $start_time = time;

        my $status = get_spider_progress_description( $db, $topic, $iteration, $i, scalar( @{ $shuffled_links } ) );
        update_topic_state( $db, $topic, $status );

        my $end = List::Util::min( $i + $ADD_NEW_LINKS_CHUNK_SIZE - 1, $#{ $shuffled_links } );
        add_new_links_chunk( $db, $topic, $iteration, [ @{ $shuffled_links }[ $i .. $end ] ] );

        my $elapsed_time = time - $start_time;
        save_metrics( $db, $topic, $iteration, $end - $i, $elapsed_time );
    }

    mine_topic_stories( $db, $topic );
}

# find any links for the topic of this iteration or less that have not already been spidered
# and call add_new_links on them.
sub spider_new_links
{
    my ( $db, $topic, $iteration ) = @_;

    my $new_links = $db->query( <<END, $iteration, $topic->{ topics_id } )->hashes;
select distinct cs.iteration, cl.* from topic_links cl, topic_stories cs
    where
        cl.ref_stories_id is null and
        cl.stories_id = cs.stories_id and
        ( cs.iteration < \$1 or cs.iteration = 1000 ) and
        cs.topics_id = \$2 and
        cl.topics_id = \$2
END

    $new_links = [ grep { !_skip_self_linked_domain( $db, $_ ) } @{ $new_links } ];

    add_new_links( $db, $topic, $iteration, $new_links );
}

# get short text description of spidering progress
sub get_spider_progress_description
{
    my ( $db, $topic, $iteration, $link_num, $total_links ) = @_;

    my $cid = $topic->{ topics_id };

    my ( $total_stories ) = $db->query( <<SQL, $cid )->flat;
select count(*) from topic_stories where topics_id = ?
SQL

    my ( $stories_last_iteration ) = $db->query( <<SQL, $cid, $iteration )->flat;
select count(*) from topic_stories where topics_id = ? and iteration = ? - 1
SQL

    my ( $queued_links ) = $db->query( <<SQL, $cid )->flat;
select count(*) from topic_links where topics_id = ? and ref_stories_id is null
SQL

    return <<END;
spidering iteration: $iteration; stories last iteration / total: $stories_last_iteration/ $total_stories; links queued: $queued_links; iteration links: $link_num / $total_links
END

}

# run the spider over any new links, for $num_iterations iterations
sub run_spider
{
    my ( $db, $topic ) = @_;

    # before we run the spider over links, we need to make sure links have been generated for all existing stories
    mine_topic_stories( $db, $topic );

    my $num_iterations = $topic->{ max_iterations };

    for my $i ( 1 .. $num_iterations )
    {
        spider_new_links( $db, $topic, $i );
    }
}

# make sure every topic story has a redirect url, even if it is just the original url
sub add_redirect_urls_to_topic_stories
{
    my ( $db, $topic ) = @_;

    my $stories = $db->query( <<END, $topic->{ topics_id } )->hashes;
select distinct s.*
    from snap.live_stories s
        join topic_stories cs on ( s.stories_id = cs.stories_id and s.topics_id = cs.topics_id )
    where cs.redirect_url is null and cs.topics_id = ?
END

    add_redirect_links( $db, $stories );
    for my $story ( @{ $stories } )
    {
        $db->query(
            "update topic_stories set redirect_url = ? where stories_id = ? and topics_id = ?",
            $story->{ redirect_url },
            $story->{ stories_id },
            $topic->{ topics_id }
        );
    }
}

# delete any stories belonging to one of the archive site sources and set any links to archive stories
# to null ref_stories_id so that they will be respidered.  this allows us to respider any archive stories
# left over before implementation of archive site redirects
sub cleanup_existing_archive_stories($$)
{
    my ( $db, $topic ) = @_;

    my $archive_media_ids = $db->query( <<SQL )->flat;
select media_id from media where name in ( 'is', 'linkis.com', 'archive.org' )
SQL

    return unless ( @{ $archive_media_ids } );

    my $media_ids_list = join( ',', @{ $archive_media_ids } );

    $db->query( <<SQL, $topic->{ topics_id } );
update topic_links tl set ref_stories_id = null
    from stories s
    where
        tl.ref_stories_id = s.stories_id and
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

    cleanup_existing_archive_stories( $db, $topic );

    # check for twitter topic here as well as in generate_topic_links, because the below query grows very
    # large without ever mining links
    if ( $topic->{ ch_monitor_id } )
    {
        INFO( "SKIP LINK GENERATION FOR TWITTER TOPIC" );
        return;
    }

    my $stories = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select distinct s.*, cs.link_mined, cs.redirect_url
    from snap.live_stories s
        join topic_stories cs on ( s.stories_id = cs.stories_id and s.topics_id = cs.topics_id )
    where
        cs.link_mined = false and
        cs.topics_id = ?
    order by s.publish_date
SQL

    generate_topic_links( $db, $topic, $stories );
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

    INFO( <<END );
dup $keep_story->{ title } [ $keep_story->{ stories_id } ] <- $delete_story->{ title } [ $delete_story->{ stories_id } ]
END

    if ( $delete_story->{ stories_id } == $keep_story->{ stories_id } )
    {
        INFO( "refusing to merge identical story" );
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

# if the given story's url domain does not match the url domain of the story,
# merge the story into another medium
sub merge_foreign_rss_story
{
    my ( $db, $topic, $story ) = @_;

    my $medium = get_cached_medium_by_id( $db, $story->{ media_id } );

    my $medium_domain = MediaWords::Util::URL::get_url_distinctive_domain( $medium->{ url } );

    # for stories in ycombinator.com, allow stories with a http://yombinator.com/.* url
    return if ( index( lc( $story->{ url } ), lc( $medium_domain ) ) >= 0 );

    my $link = { url => $story->{ url } };

    # note that get_matching_story_from_db will not return $story b/c it now checkes for foreign_rss_links = true
    my $merge_into_story = get_matching_story_from_db( $db, $link )
      || add_new_story( $db, undef, $story, $topic );

    merge_dup_story( $db, $topic, $story, $merge_into_story );
}

# find all topic stories with a foreign_rss_links medium and merge each story
# into a different medium unless the story's url domain matches that of the existing
# medium.
sub merge_foreign_rss_stories
{
    my ( $db, $topic ) = @_;

    my $foreign_stories = $db->query( <<END, $topic->{ topics_id } )->hashes;
select s.* from stories s, topic_stories cs, media m
    where s.stories_id = cs.stories_id and s.media_id = m.media_id and
        m.foreign_rss_links = true and cs.topics_id = ? and
        not cs.valid_foreign_rss_story
END

    map { merge_foreign_rss_story( $db, $topic, $_ ) } @{ $foreign_stories };
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

    $download = MediaWords::DBI::Downloads::store_content( $db, $download, \$content );

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

    return if ( $topic->{ ch_monitor_id } );

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
    my $iterator = List::MoreUtils::natatime( $ADD_NEW_LINKS_CHUNK_SIZE, @{ $seed_urls } );
    while ( my @seed_urls_chunk = $iterator->() )
    {
        my $non_content_urls = [];
        for my $csu ( @seed_urls_chunk )
        {
            if ( $csu->{ content } )
            {
                my $story = get_matching_story_from_db( $db, $csu )
                  || add_new_story( $db, $csu, undef, $topic, 0, 1 );
                add_to_topic_stories_if_match( $db, $topic, $story, $csu );
            }
            else
            {
                push( @{ $non_content_urls }, $csu );
            }
        }

        add_new_links( $db, $topic, 0, $non_content_urls );

        $db->begin;
        for my $seed_url ( @seed_urls_chunk )
        {
            my $story = $seed_url->{ story };
            my $set_stories_id = $story ? $story->{ stories_id } : undef;
            $db->query( <<END, $set_stories_id, $seed_url->{ topic_seed_urls_id } );
update topic_seed_urls set stories_id = ?, processed = 't' where topic_seed_urls_id = ?
END
        }

        # cleanup any topic_seed_urls pointing to a merged story
        $db->execute_with_large_work_mem(
            <<SQL,
            UPDATE topic_seed_urls AS tsu
            SET stories_id = tms.target_stories_id
            FROM topic_merged_stories_map AS tms,
                 topic_stories ts
            WHERE tsu.stories_id = tms.source_stories_id
              AND ts.stories_id = tms.target_stories_id
              AND tsu.topics_id = ts.topics_id
              AND ts.topics_id = \$1
SQL
            $topic->{ topics_id }
        );

        $db->commit;
    }

    return 1;
}

# look for any stories in the topic tagged with a date method of 'current_time' and
# assign each the earliest source link date if any source links exist
sub add_source_link_dates
{
    my ( $db, $topic ) = @_;

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

# make a pass through all broken stories caching any broken downloads
# using MediaWords::Util::Web::Cache::cache_link_downloads().  these will get
# fetched with ::Web::Cache::get_cached_link_download and then stored via
# MediaWords::DBI::Stories::fix_story_downloads_if_needed
# later in the process, but we have to cache the downloads now so that we can do the
# downloads in one big parallel job rather than one at a time.
sub cache_broken_story_downloads
{
    my ( $db, $stories ) = @_;

    my $fetch_links = [];
    for my $story ( @{ $stories } )
    {
        my $downloads = $db->query( <<END, $story->{ stories_id } )->hashes;
select * from downloads where stories_id = ? order by downloads_id
END
        my $broken_downloads = [ grep { MediaWords::DBI::Stories::download_is_broken( $db, $_ ) } @{ $downloads } ];

        map { $story->{ cached_downloads }->{ $_->{ downloads_id } } = $_ } @{ $broken_downloads };

        push( @{ $fetch_links }, @{ $broken_downloads } );
    }

    MediaWords::Util::Web::Cache::cache_link_downloads( $fetch_links );
}

# get the story in pick_list that appears first in ref_list
sub pick_first_matched_story
{
    my ( $ref_list, $pick_list ) = @_;

    for my $ref ( @{ $ref_list } )
    {
        for my $pick ( @{ $pick_list } )
        {
            return $pick if ( $ref->{ stories_id } == $pick->{ stories_id } );
        }
    }

    LOGCONFESS( "can't find any pick element in reference list" );
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

# add to topic stories if the story is not already in the topic and it
# assume_match is true or the story matches the topic pattern
sub add_to_topic_stories_if_match
{
    my ( $db, $topic, $story, $link, $assume_match ) = @_;

    TRACE "add story if match: $story->{ url }";

    set_topic_link_ref_story( $db, $story, $link ) if ( $link->{ topic_links_id } );

    return if ( skip_topic_story( $db, $topic, $story, $link ) );

    if ( $assume_match || $link->{ assume_match } || story_matches_topic_pattern( $db, $topic, $story ) )
    {
        TRACE "TOPIC MATCH: $link->{ url }";
        $link->{ iteration } ||= 0;
        add_to_topic_stories( $db, $topic, $story, $link->{ iteration } + 1, 0 );
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

# get lookup hash with the normalized url as the key for the
# the topic_links or topic_seed_urls associated with the
# given story and topic
sub get_redirect_url_lookup
{
    my ( $db, $story, $topic, $table ) = @_;

    my $story_field = get_story_field_from_url_table( $table );

    my $rows = $db->query( <<END, $story->{ stories_id }, $topic->{ topics_id } )->hashes;
select a.* from ${ table } a where ${ story_field } = ? and topics_id = ?
END
    my $lookup = {};
    map { push( @{ $lookup->{ MediaWords::Util::URL::normalize_url_lossy( $_->{ url } ) } }, $_ ) } @{ $rows };

    return $lookup;
}

# set the given topic_links or topic_seed_urls to point to the given story
sub unredirect_story_url
{
    my ( $db, $story, $url, $lookup, $table ) = @_;

    my $story_field = get_story_field_from_url_table( $table );

    my $nu = MediaWords::Util::URL::normalize_url_lossy( $url->{ url } );

    for my $row ( @{ $lookup->{ $nu } } )
    {
        INFO "unredirect url: $row->{ url }, $table, $story->{ stories_id }";
        $db->query( <<END, $story->{ stories_id }, $row->{ "${ table }_id" } );
update ${ table } set ${ story_field } = ? where ${ table }_id = ?
END
    }
}

# reprocess the urls that redirected into the given story.
# $urls should be a list of hashes with the following fields:
# url, assume_match, manual_redirect
# if assume_match is true, assume that the story created from the
# url matches the topic.  If manual_redirect is set, manually
# set the redirect_url to the value (for manually inputting redirects
# for dead links).
sub unredirect_story
{
    my ( $db, $topic, $story, $urls ) = @_;

    for my $u ( grep { $_->{ manual_redirect } } @{ $urls } )
    {
        $u->{ redirect_url } = $u->{ manual_redirect };
    }

    MediaWords::Util::Web::Cache::cache_link_downloads( $urls );

    my $cl_lookup  = get_redirect_url_lookup( $db, $story, $topic, 'topic_links' );
    my $csu_lookup = get_redirect_url_lookup( $db, $story, $topic, 'topic_seed_urls' );

    for my $url ( @{ $urls } )
    {
        my $new_story = get_matching_story_from_db( $db, $url )
          || add_new_story( $db, $url, undef, $topic );

        add_to_topic_stories_if_match( $db, $topic, $new_story, $url, $url->{ assume_match } );

        unredirect_story_url( $db, $new_story, $url, $cl_lookup,  'topic_links' );
        unredirect_story_url( $db, $new_story, $url, $csu_lookup, 'topic_seed_urls' );

        $db->query( <<END, $story->{ stories_id }, $topic->{ topics_id } );
delete from topic_stories where stories_id = ? and topics_id = ?
END
    }
}

# a list of all original urls that were redirected to the url for the given story
# along with the topic in which that url was found, returned as a list
# of hashes with the fields { url, topics_id, topic_name }
sub get_story_original_urls
{
    my ( $db, $story ) = @_;

    my $urls = $db->query( <<'END', $story->{ stories_id } )->hashes;
select q.url, q.topics_id, c.name topic_name
    from
        (
            select distinct topics_id, url from topic_links where ref_stories_id = $1
            union
            select topics_id, url from topic_seed_urls where stories_id = $1
         ) q
         join topics c on ( c.topics_id = q.topics_id )
    order by c.name, q.url
END

    my $normalized_urls_map = {};
    for my $url ( @{ $urls } )
    {
        my $nu = MediaWords::Util::URL::normalize_url_lossy( $url->{ url } );
        $normalized_urls_map->{ $nu } = $url;
    }

    my $normalized_urls = [];
    while ( my ( $nu, $url ) = each( %{ $normalized_urls_map } ) )
    {
        $url->{ url } = $nu;
        push( @{ $normalized_urls }, $url );
    }

    return $normalized_urls;
}

# given a list of stories, keep the story with the shortest title and
# merge the other stories into that story
sub merge_dup_stories
{
    my ( $db, $topic, $stories ) = @_;

    my $stories_ids_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $story_sentence_counts = $db->query( <<END )->hashes;
select stories_id, count(*) sentence_count from story_sentences where stories_id in ($stories_ids_list) group by stories_id
END

    my $ssc = {};
    map { $ssc->{ $_->{ stories_id } } = 0 } @{ $stories };
    map { $ssc->{ $_->{ stories_id } } = $_->{ sentence_count } } @{ $story_sentence_counts };

    $stories = [ sort { $ssc->{ $b->{ stories_id } } <=> $ssc->{ $a->{ stories_id } } } @{ $stories } ];

    my $keep_story = shift( @{ $stories } );

    INFO "duplicates: $keep_story->{ title } [$keep_story->{ url } $keep_story->{ stories_id }]";
    map { INFO "\t$_->{ title } [$_->{ url } $_->{ stories_id }]"; } @{ $stories };

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

    for my $get_dup_stories (
        \&MediaWords::DBI::Stories::get_medium_dup_stories_by_url,
        \&MediaWords::DBI::Stories::get_medium_dup_stories_by_title
      )
    {
        # regenerate story list each time to capture previously merged stories
        my $media_lookup = get_topic_stories_by_medium( $db, $topic );

        while ( my ( $media_id, $stories ) = each( %{ $media_lookup } ) )
        {
            my $dup_stories = $get_dup_stories->( $db, $stories );
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

    my $date_clause = "publish_date:[$solr_start TO $solr_end]";

    return $date_clause;
}

# get the full solr query by combining the solr_seed_query with generated clauses for start and
# end date from topics and media clauses from topics_media_map and topics_media_tags_map.
# only return a query for up to a month of the given a query, using the zero indexed $month_offset to
# fetch $month_offset to return months after the first.  return undef if the month_offset puts the
# query start date beyond the topic end date
sub get_full_solr_query($$;$$$$)
{
    my ( $db, $topic, $media_ids, $media_tags_ids, $month_offset ) = @_;

    $month_offset ||= 0;

    my $date_clause = get_solr_query_month_clause( $topic, $month_offset );

    return undef unless ( $date_clause );

    my $solr_query = "( " . $topic->{ solr_seed_query } . " ) and $date_clause";

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

    DEBUG( "full solr query: $solr_query" );

    return $solr_query;
}

# import a single month of the solr seed query.  we do this to avoid giant queries that timeout in solr.
sub import_solr_seed_query_month($$$)
{
    my ( $db, $topic, $month_offset ) = @_;

    my $max_stories = $topic->{ max_stories };

    # if solr maxes out on returned stories, it returns a few documents less than the rows= parameter, so we
    # assume that we hit the solr max if we are within 5% of the ma stories
    my $max_returned_stories = $max_stories * 0.95;

    my $solr_query = get_full_solr_query( $db, $topic, undef, undef, $month_offset );

    # this should return undef once the month_offset gets too big
    return undef unless ( $solr_query );

    INFO "import solr seed query month offset $month_offset";
    INFO "executing solr query: $solr_query";
    my $stories = MediaWords::Solr::search_for_stories( $db, { q => $solr_query, rows => $max_stories } );

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

    return if ( $topic->{ solr_seed_query_run } );

    my $month_offset = 0;
    while ( import_solr_seed_query_month( $db, $topic, $month_offset++ ) ) { }

    $db->query( "update topics set solr_seed_query_run = 't' where topics_id = ?", $topic->{ topics_id } );
}

# return true if there are fewer than $MAX_NULL_BITLY_STORIES stories without bitly data
sub all_bitly_data_fetched
{
    my ( $db, $topic ) = @_;

    my ( $num_topic_stories ) = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select count(*) from topic_stories where topics_id = ?
SQL

    my $max_nulls = int( $MAX_NULL_BITLY_STORIES * $num_topic_stories ) + 1;

    DEBUG( "all bitly data fetched: $num_topic_stories topic stories total, $max_nulls max nulls" );

    my $null_bitly_story = $db->query( <<SQL, $topic->{ topics_id }, $max_nulls )->hash;
select 1
    from topic_stories cs
        left join bitly_clicks_total b on ( cs.stories_id = b.stories_id )
    where
        cs.topics_id = ? and
        b.click_count is null
    limit 1
    offset ?
SQL

    DEBUG( "all bitly data fetched: " . ( $null_bitly_story ? 'no' : 'yes' ) );

    return !$null_bitly_story;
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

# send high priority jobs to fetch bitly and facebook data for all stories that don't yet have it
sub fetch_social_media_data ($$)
{
    my ( $db, $topic ) = @_;

    # test spider should be able to run with job broker, so we skip social media collection
    return if ( $_test_mode );

    my $cid = $topic->{ topics_id };

    MediaWords::Job::Bitly::FetchStoryStats->add_topic_stories_to_queue( $db, $topic );
    MediaWords::Job::Facebook::FetchStoryStats->add_topic_stories_to_queue( $db, $topic );

    my $poll_wait = 30;
    my $retries   = int( $MAX_SOCIAL_MEDIA_FETCH_TIME / $poll_wait ) + 1;

    for my $i ( 1 .. $retries )
    {
        return if ( all_bitly_data_fetched( $db, $topic ) && all_facebook_data_fetched( $db, $topic ) );
        sleep $poll_wait;
    }

    LOGCONFESS( "Timed out waiting for social media data" );
}

# mine the given topic for links and to recursively discover new stories on the web.
# options:
#   import_only - only run import_seed_urls and import_solr_seed and exit
#   cache_broken_downloads - speed up fixing broken downloads, but add time if there are no broken downloads
#   skip_outgoing_foreign_rss_links - skip slow process of adding links from foreign_rss_links media
#   skip_post_processing - skip social media fetching and snapshotting
sub do_mine_topic ($$;$)
{
    my ( $db, $topic, $options ) = @_;

    map { $options->{ $_ } ||= 0 }
      qw/cache_broken_downloads import_only skip_outgoing_foreign_rss_links skip_post_processing test_mode/;

    # Log activity that is about to start
    MediaWords::DBI::Activities::log_system_activity( $db, 'tm_mine_topic', $topic->{ topics_id }, $options )
      || LOGCONFESS( "Unable to log the 'tm_mine_topic' activity." );

    update_topic_state( $db, $topic, "fetching tweets" );
    fetch_and_import_twitter_urls( $db, $topic );

    update_topic_state( $db, $topic, "importing solr seed query" );
    import_solr_seed_query( $db, $topic );

    update_topic_state( $db, $topic, "importing seed urls" );
    if ( import_seed_urls( $db, $topic ) )
    {
        # merge dup media and stories here to avoid redundant link processing for imported urls
        update_topic_state( $db, $topic, "merging duplicate media stories" );
        merge_dup_media_stories( $db, $topic );

        update_topic_state( $db, $topic, "merging duplicate stories" );
        find_and_merge_dup_stories( $db, $topic );

        update_topic_state( $db, $topic, "merging foreign rss stories" );
        merge_foreign_rss_stories( $db, $topic );

        update_topic_state( $db, $topic, "adding redirect urls to topic stories" );
        add_redirect_urls_to_topic_stories( $db, $topic );
    }

    unless ( $options->{ import_only } )
    {
        update_topic_state( $db, $topic, "running spider" );
        run_spider( $db, $topic );

        # merge dup media and stories again to catch dups from spidering
        update_topic_state( $db, $topic, "merging duplicate media stories" );
        merge_dup_media_stories( $db, $topic );

        update_topic_state( $db, $topic, "merging duplicate stories" );
        find_and_merge_dup_stories( $db, $topic );

        update_topic_state( $db, $topic, "adding source link dates" );
        add_source_link_dates( $db, $topic );

        update_topic_state( $db, $topic, "analyzing topic tables" );
        $db->query( "analyze topic_stories" );
        $db->query( "analyze topic_links" );

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
