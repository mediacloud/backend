package MediaWords::CM::Mine;

# Mine through stories found for the given controversy and find all the links in each story.
# Find each link, try to find whether it matches any given story.  If it doesn't, create a
# new story.  Add that story's links to the queue if it matches the pattern for the
# controversy.  Write the resulting stories and links to controversy_stories and controversy_links.

use strict;
use warnings;

use Carp;
use Data::Dumper;
use DateTime;
use Encode;
use Getopt::Long;
use HTML::LinkExtractor;
use List::Util;
use Parallel::ForkManager;
use Readonly;
use URI;
use URI::Split;
use URI::Escape;

use MediaWords::CM::GuessDate;
use MediaWords::CM::GuessDate::Result;
use MediaWords::DB;
use MediaWords::DBI::Activities;
use MediaWords::DBI::Media;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::GuessDate;
use MediaWords::Solr;
use MediaWords::Util::HTML;
use MediaWords::Util::SQL;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;
use MediaWords::Util::Web;
use MediaWords::Util::Bitly;
use MediaWords::GearmanFunction::Bitly::EnqueueAllControversyStories;

# number of times to run through the recursive link weight process
Readonly my $LINK_WEIGHT_ITERATIONS => 3;

# max number of solely self linked stories to include
Readonly my $MAX_SELF_LINKED_STORIES => 100;

# ignore links that match this pattern
my $_ignore_link_pattern =
  '(www.addtoany.com)|(novostimira.com)|(ads\.pheedo)|(www.dailykos.com\/user)|' .
  '(livejournal.com\/(tag|profile))|(sfbayview.com\/tag)|(absoluteastronomy.com)|' .
  '(\/share.*http)|(digg.com\/submit)|(facebook.com.*mediacontentsharebutton)|' .
  '(feeds.wordpress.com\/.*\/go)|(sharetodiaspora.github.io\/)|(iconosquare.com)|' .
  '(unz.com)|(answers.com)|(downwithtyranny.com\/search)|(scoop\.?it)|(sco\.lt)|' .
  '(pronk.*\.wordpress\.com\/(tag|category))|(wn\.com)';

# cache of media by media id
my $_media_cache = {};

# cache for spidered:spidered tag
my $_spidered_tag;

# cache of media by sanitized url
my $_media_url_lookup;

# lookup of self linked domains, for efficient skipping before adding a story
my $_skip_self_linked_domain = {};

# fetch each link and add a { redirect_url } field if the
# { url } field redirects to another url
sub add_redirect_links
{
    my ( $db, $links ) = @_;

    my $urls = [ map { URI->new( $_->{ url } )->as_string } @{ $links } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    my $link_lookup = {};
    map { $link_lookup->{ URI->new( $_->{ url } )->as_string } = $_ } @{ $links };

    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        my $final_url    = $response->request->uri->as_string;
        my $link         = $link_lookup->{ $original_url };
        $link->{ redirect_url } = $final_url;
    }
}

my $_link_extractor;

# return a list of all links that appear in the html
sub get_links_from_html
{
    my ( $html, $url ) = @_;

    # we choose not to pass the base url here to avoid collecting relative urls.  we end up with too many
    # stories linked from the same media source when we allow relative links.
    $_link_extractor ||= new HTML::LinkExtractor();

    $_link_extractor->parse( \$html );

    my $links = [];
    for my $link ( @{ $_link_extractor->links } )
    {
        next if ( !$link->{ href } );

        next if ( $link->{ href } !~ /^http/i );

        next if ( $link->{ href } =~ $_ignore_link_pattern );

        $link =~ s/www[a-z0-9]+.nytimes/www.nytimes/i;

        push( @{ $links }, { url => $link->{ href } } );
    }

    return $links;
}

sub get_cached_medium_by_id
{
    my ( $db, $media_id ) = @_;

    if ( !$_media_cache )
    {
        my $all_media = $db->query( "select * from media" )->hashes;
        map { $_media_cache->{ $_->{ media_id } } = $_ } @{ $all_media };
    }

    $_media_cache->{ $media_id } ||= $db->find_by_id( 'media', $media_id );

    return $_media_cache->{ $media_id };
}

# return true if the media the story belongs to has full_text_rss set to true
sub story_media_has_full_text_rss
{
    my ( $db, $story ) = @_;

    my $media_id = $story->{ media_id };

    my $medium = get_cached_medium_by_id( $db, $story->{ media_id } );

    return $medium->{ full_text_rss };
}

# get links at end of boingboing link
sub get_boingboing_links
{
    my ( $db, $story ) = @_;

    return [] unless ( $story->{ url } =~ /boingboing.org/ );

    my $download = $db->query( "select * from downloads where stories_id = ?", $story->{ stories_id } )->hash;

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );

    my $content = ${ $content_ref };

    if ( !( $content =~ s/((<div class="previously2">)|(class="sharePost")).*//ms ) )
    {
        warn( "Unable to find end pattern" );
        return [];
    }

    if ( !( $content =~ s/.*<a href[^>]*>[^<]*<\/a> at\s+\d+\://ms ) )
    {
        warn( "Unable to find begin pattern" );
        return [];
    }

    return get_links_from_html( $content, $story->{ url } );
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
        $download = $db->find_by_id( 'downloads', $download->{ downloads_id } );
        eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };
        warn( "error refetching content: $@" ) if ( $@ );
    }

    return $content_ref ? $$content_ref : '';
}

# parse the full first download of the given story for youtube embeds
sub get_youtube_embed_links
{
    my ( $db, $story ) = @_;

    my $html = get_first_download_content( $db, $story );

    my $links = [];
    while ( $html =~ /src\=[\'\"]((http:)?\/\/(www\.)?youtube(-nocookie)?\.com\/[^\'\"]*)/g )
    {
        my $url = $1;

        $url = "http:$url/" unless ( $url =~ /^http/ );

        $url =~ s/\?.*//;
        $url =~ s/\/$//;
        $url =~ s/youtube-nocookie/youtube/i;

        push( @{ $links }, { url => $url } );
    }

    return $links;
}

# get the extracted html for the story.  fix the story downloads by redownloading
# as necessary
sub get_extracted_html
{
    my ( $db, $story ) = @_;

    my $extracted_html;
    eval { $extracted_html = MediaWords::DBI::Stories::get_extracted_html_from_db( $db, $story ); };
    if ( $@ )
    {
        # say STDERR "fixing story download: $@";
        MediaWords::DBI::Stories::fix_story_downloads_if_needed( $db, $story );
        eval { $extracted_html = MediaWords::DBI::Stories::get_extracted_html_from_db( $db, $story ); };
    }

    return $extracted_html;
}

# get all urls that appear in the text or description of the story using a simple kludgy regex
sub get_links_from_story_text
{
    my ( $db, $story ) = @_;

    my $text = MediaWords::DBI::Stories::get_text( $db, $story );

    my $links = [];
    while ( $text =~ m~(https?://[^\s\")]+)~g )
    {
        my $url = $1;

        $url =~ s/\W+$//;

        push( @{ $links }, { url => $url } );
    }

    return $links;
}

# find any links in the extracted html or the description of the story.
sub get_links_from_story
{
    my ( $db, $story ) = @_;

    print STDERR "mining $story->{ title } [$story->{ url }] ...\n";

    my $extracted_html = get_extracted_html( $db, $story );

    my $links = get_links_from_html( $extracted_html, $story->{ url } );
    my $text_links = get_links_from_story_text( $db, $story );
    my $description_links = get_links_from_html( $story->{ description }, $story->{ url } );
    my $boingboing_links = get_boingboing_links( $db, $story );
    my $youtube_links = get_youtube_embed_links( $db, $story );

    my @all_links = ( @{ $links }, @{ $text_links }, @{ $description_links }, @{ $boingboing_links } );

    @all_links = grep { $_->{ url } !~ $_ignore_link_pattern } @all_links;

    my $link_lookup = {};
    map { $link_lookup->{ MediaWords::Util::URL::normalize_url_lossy( $_->{ url } ) } = $_ } @all_links;

    return [ values( %{ $link_lookup } ) ];
}

# return true if the publish date of the story is within 7 days of the controversy date range or if the
# story is undateable
sub story_within_controversy_date_range
{
    my ( $db, $controversy, $story ) = @_;

    my $story_date = substr( $story->{ publish_date }, 0, 10 );

    if ( !$controversy->{ start_date } )
    {
        my ( $start_date, $end_date ) = $db->query( <<SQL, $controversy->{ controversies_id } )->flat;
select start_date, end_date from controversy_dates where controversies_id = ? and boundary
SQL
        $controversy->{ start_date } = $start_date;
        $controversy->{ end_date }   = $end_date;
    }

    my $start_date = $controversy->{ start_date };
    $start_date = MediaWords::Util::SQL::increment_day( $start_date, -7 );
    $start_date = substr( $start_date, 0, 10 );

    my $end_date = $controversy->{ end_date };
    $end_date = MediaWords::Util::SQL::increment_day( $end_date, 7 );
    $end_date = substr( $end_date, 0, 10 );

    return 1 if ( ( $story_date ge $start_date ) && ( $story_date le $end_date ) );

    return MediaWords::DBI::Stories::GuessDate::is_undateable( $db, $story );
}

# for each story, return a list of the links found in either the extracted html or the story description
sub generate_controversy_links
{
    my ( $db, $controversy, $stories ) = @_;

    my $max_processes = 16;

    my $pm = new Parallel::ForkManager( $max_processes );

    say STDERR "GENERATE CONTROVERSY LINKS: " . scalar( @{ $stories } );

    # make sure db changes are visible to forked processes
    $db->commit;

    for my $story ( @{ $stories } )
    {
        $pm->start and next;

        $db = MediaWords::DB::reset_forked_db( $db );

        $db->dbh->{ AutoCommit } = 0;

        my $story_in_date_range = story_within_controversy_date_range( $db, $controversy, $story );

        if ( !$story_in_date_range )
        {
            say STDERR "OUT OF DATE RANGE: $story->{ publish_date }" unless ( $story_in_date_range );
        }
        else
        {
            say STDERR "IN DATE RANGE: $story->{ publish_date }" unless ( $story_in_date_range );

            my $links = $story_in_date_range ? get_links_from_story( $db, $story ) : [];

            my $link_lookup = {};

            for my $link ( @{ $links } )
            {
                next if ( ( $link->{ url } eq $story->{ url } ) || _skip_self_linked_domain( $db, $link ) );

                my $link_exists = $link_lookup->{ $link->{ url } };
                $link_lookup->{ $link->{ url } } = 1;

                $link_exists ||= $db->query(
                    "select * from controversy_links where stories_id = ? and url = ? and controversies_id = ?",
                    $story->{ stories_id },
                    encode( 'utf8', $link->{ url } ),
                    $controversy->{ controversies_id }
                )->hash;

                if ( $link_exists )
                {
                    print STDERR "    -> dup: $link->{ url }\n";
                }
                else
                {
                    print STDERR "    -> new: $link->{ url }\n";
                    $db->create(
                        "controversy_links",
                        {
                            stories_id       => $story->{ stories_id },
                            url              => encode( 'utf8', $link->{ url } ),
                            controversies_id => $controversy->{ controversies_id }
                        }
                    );
                }
            }
        }

        $db->query(
            "update controversy_stories set link_mined = true where stories_id = ? and controversies_id = ?",
            $story->{ stories_id },
            $controversy->{ controversies_id }
        );

        $db->commit;

        $pm->finish;
    }

    $pm->wait_all_children;
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

            croak( "foreign rss medium $medium->{ media_id }" ) if ( $medium->{ foreign_rss_links } );
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
        warn( "Unable to find host name in url: $normalized_url ($story_url)" );
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
        name      => encode( 'utf8', $medium_name ),
        url       => encode( 'utf8', $medium_url ),
        moderated => 't',
    };

    $medium = $db->create( 'media', $medium );

    print STDERR "add medium: $medium_name / $medium_url / $medium->{ media_id }\n";

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
    order by ( name = 'Controversy Spider Feed' )
END

    my $feed = $db->query( $feed_query, $medium->{ media_id }, $medium->{ url } )->hash;

    return $feed if ( $feed );

    $db->query(
        "insert into feeds ( media_id, url, name, feed_status ) " .
          "  values ( ?, ?, 'Controversy Spider Feed', 'inactive' )",
        $medium->{ media_id },
        $medium->{ url }
    );

    return $db->query( $feed_query, $medium->{ media_id }, $medium->{ url } )->hash;
}

# return true if the args are valid date arguments.  assume a date has to be between 2000 and 2040.
sub valid_date_parts
{
    my ( $year, $month, $day ) = @_;

    return 0 if ( ( $year < 2000 ) || ( $year > 2040 ) );

    return Date::Parse::str2time( "$year-$month-$day" );
}

# extract the story for the given download
sub extract_download
{
    my ( $db, $download ) = @_;

    return if ( $download->{ url } =~ /jpg|pdf|doc|mp3|mp4|zip$/i );

    return if ( $download->{ url } =~ /livejournal.com\/(tag|profile)/i );

    my $dt = $db->query( "select 1 from download_texts where downloads_id = ?", $download->{ downloads_id } )->hash;
    return if ( $dt );

    eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "controversy", 0, 1 ); };

    if ( my $error = $@ )
    {
        if ( ref( $error ) )
        {
            # ugliness needed to avoid passing object to $db->query below
            my $thrift_error = UNIVERSAL::isa( $error, 'Thrift::TException' );
            $error = $thrift_error ? "$error->{ code } $error->{ message }" : $error . '';
        }

        warn "extract error processing download $download->{ downloads_id }: $error";
    }
    else
    {
        my $story = $db->find_by_id( 'stories', $download->{ stories_id } );
        add_missing_story_sentences( $db, $story );
    }
}

# get a date for a new story by trying each of the following, in this order:
# * assigning a date from the merged old story,
# * guessing the date using MediaWords::CM::GuessDate,
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
        $source_story = $db->find_by_id( 'stories', $source_link->{ stories_id } );
        $story->{ publish_date } = $source_story->{ publish_date };
    }

    my $date = MediaWords::CM::GuessDate::guess_date( $db, $story, $story_content, 1 );
    if ( $date->{ result } eq $MediaWords::CM::GuessDate::Result::FOUND )
    {
        return ( $date->{ guess_method }, $date->{ date } );
    }
    elsif ( $date->{ result } eq $MediaWords::CM::GuessDate::Result::INAPPLICABLE )
    {
        return ( 'undateable', $source_story ? $source_story->{ publish_date } : MediaWords::Util::SQL::sql_now );
    }

    return ( 'current_time', MediaWords::Util::SQL::sql_now );
}
my $reliable_methods = [ qw(guess_by_url guess_by_url_and_date_text merged_story_rss manual) ];

# recursively search for the medium pointed to by dup_media_id
# by the media_id medium.  return the first medium that does not have a dup_media_id.
sub get_dup_medium
{
    my ( $db, $media_id, $allow_foreign_rss_links, $count ) = @_;

    croak( "loop detected" ) if ( $count && ( $count > 10 ) );

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

    return 0 unless ( $link->{ redirect_url } && ( $link->{ redirect_url } ne $link->{ url } ) );

    my ( $medium_url, $medium_name ) = generate_medium_url_and_name_from_url( $link->{ redirect_url } );

    my $u = MediaWords::Util::URL::normalize_url_lossy( $medium_url );

    my $match = $db->query( "select 1 from controversy_ignore_redirects where url = ?", $u )->hash;

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
        title        => encode( 'utf8', $old_story->{ title } ),
        publish_date => $link->{ publish_date },
        description  => ''
    };

    if ( $link->{ publish_date } )
    {
        return ( $story, 'manual' );
    }
    else
    {
        my ( $date_guess_method, $publish_date ) = get_new_story_date( $db, $story, $story_content, $old_story, $link );
        print STDERR "date guess: $date_guess_method: $publish_date\n";

        $story->{ publish_date } = $publish_date;
        return ( $story, $date_guess_method );
    }
}

# wrap create story in eval
sub safely_create_story
{
    my ( $db, $story ) = @_;

    eval { $story = $db->create( 'stories', $story ) };
    carp( $@ . " - " . Dumper( $story ) ) if ( $@ );

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
        host       => lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] ),
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

# add a new story and download corresponding to the given link or existing story
sub add_new_story
{
    my ( $db, $link, $old_story, $controversy, $allow_foreign_rss_links, $check_pattern, $skip_extraction ) = @_;

    die( "only one of $link or $old_story should be set" ) if ( $link && $old_story );

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
        $story_content = MediaWords::Util::Web::get_cached_link_download( $link );
        $link->{ redirect_url } ||= MediaWords::Util::Web::get_cached_link_download_redirect_url( $link );

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

    print STDERR "add_new_story: $old_story->{ url }\n";

    # if neither the url nor the content match the pattern, it cannot be a match so return and don't add the story
    if (
        $check_pattern
        && !potential_story_matches_controversy_pattern(
            $controversy, $link->{ url }, $link->{ redirect_url }, $story_content
        )
      )
    {
        say STDERR "SKIP - NO POTENTIAL MATCH";
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

    print STDERR "add story: $story->{ title } / $story->{ url } / $story->{ publish_date } / $story->{ stories_id }\n";

    $db->create( 'feeds_stories_map', { feeds_id => $feed->{ feeds_id }, stories_id => $story->{ stories_id } } );

    my $download = create_download_for_new_story( $db, $story, $feed );

    MediaWords::DBI::Downloads::store_content_determinedly( $db, $download, $story_content );

    extract_download( $db, $download ) unless ( $skip_extraction );

    return $story;
}

# remove the given story from the given controversy
sub remove_story_from_controversy($$$)
{
    my ( $db, $stories_id, $controversies_id ) = @_;

    $db->query(
        <<EOF,
        DELETE FROM controversy_stories
        WHERE stories_id = ?
          AND controversies_id = ?
EOF
        $stories_id, $controversies_id
    );
}

# return true if any of the download_texts for the story matches the controversy search pattern
sub story_download_text_matches_pattern
{
    my ( $db, $story, $controversy ) = @_;

    my $dt = $db->query( <<END, $story->{ stories_id }, $controversy->{ controversies_id } )->hash;
select 1
    from download_texts dt
        join downloads d on ( dt.downloads_id = d.downloads_id )
        join controversies c on ( c.controversies_id = \$2 )
    where
        d.stories_id = \$1 and
        dt.download_text ~ ( '(?isx)' || c.pattern )
    limit 1
END
    return $dt ? 1 : 0;
}

# return true if any of the story_sentences with no duplicates for the story matches the controversy search pattern
sub story_sentence_matches_pattern
{
    my ( $db, $story, $controversy ) = @_;

    my $ss = $db->query( <<END, $story->{ stories_id }, $controversy->{ controversies_id } )->hash;
select 1
    from story_sentences ss
        join controversies c on ( c.controversies_id = \$2 )
    where
        ss.stories_id = \$1 and
        ss.sentence ~ ( '(?isx)' || c.pattern ) and
        ( ( is_dup is null ) or not ss.is_dup )
    limit 1
END

    return $ss ? 1 : 0;
}

# translate postgres word break patterns ([[:<>:]]) into perl (\b)
sub translate_pattern_to_perl
{
    my ( $s ) = @_;

    $s =~ s/\[\[\:[\<\>]\:\]\]/\\b/g;

    return $s;
}

my $_no_potential_match_urls = {};

# test whether the url or content of a potential story matches the controversy pattern
sub potential_story_matches_controversy_pattern
{
    my ( $controversy, $url, $redirect_url, $content ) = @_;

    my $re = translate_pattern_to_perl( $controversy->{ pattern } );

    my $match = ( ( $redirect_url =~ /$re/isx ) || ( $url =~ /$re/isx ) || ( $content =~ /$re/isx ) ) ? 1 : 0;

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

my $_story_sentences_added = {};

# add missing story sentences, but only do so once per runtime so that we don't repeatedly try
# to add sentences to stories with no sentences
sub add_missing_story_sentences
{
    my ( $db, $story ) = @_;

    return if ( $_story_sentences_added->{ $story->{ stories_id } } );

    MediaWords::DBI::Stories::add_missing_story_sentences( $db, $story );

    $_story_sentences_added->{ $story->{ stories_id } } = 1;
}

# return the type of match if the story title, url, description, or sentences match controversy search pattern.
# return undef if no match is found.
sub story_matches_controversy_pattern
{
    my ( $db, $controversy, $story, $metadata_only ) = @_;

    my $perl_re = translate_pattern_to_perl( $controversy->{ pattern } );

    for my $field ( qw/title description url redirect_url/ )
    {
        if ( $story->{ $field } && ( $story->{ $field } =~ /$perl_re/isx ) )
        {
            return $field;
        }
    }

    return 0 if ( $metadata_only );

    # # check for download_texts match first because some stories don't have
    # # story_sentences, and it is expensive to generate the missing story_sentences
    # return 0 unless ( story_download_text_matches_pattern( $db, $story, $controversy ) );

    return story_sentence_matches_pattern( $db, $story, $controversy ) ? 'sentence' : 0;
}

# add to controversy_stories table
sub add_to_controversy_stories
{
    my ( $db, $controversy, $story, $iteration, $link_mined, $valid_foreign_rss_story ) = @_;

    $db->query(
"insert into controversy_stories ( controversies_id, stories_id, iteration, redirect_url, link_mined, valid_foreign_rss_story ) "
          . "  values ( ?, ?, ?, ?, ?, ? )",
        $controversy->{ controversies_id },
        $story->{ stories_id },
        $iteration, $story->{ url },
        $link_mined, $valid_foreign_rss_story
    );
}

# add story to controversy_stories table and mine for controversy_links
sub add_to_controversy_stories_and_links
{
    my ( $db, $controversy, $story, $iteration ) = @_;

    add_to_controversy_stories( $db, $controversy, $story, $iteration );

    generate_controversy_links( $db, $controversy, [ $story ] );
}

# return true if the domain of the story url matches the domain of the medium url
sub _story_domain_matches_medium
{
    my ( $db, $medium, $url, $redirect_url ) = @_;

    my $medium_domain = MediaWords::Util::URL::get_url_domain( $medium->{ url } );

    my $story_domains = [ map { MediaWords::Util::URL::get_url_domain( $_ ) } ( $url, $redirect_url ) ];

    return ( grep { $medium_domain eq $_ } @{ $story_domains } ) ? 1 : 0;
}

# given a set of possible story matches, find the story that is likely the best.
# the best story is the one that sorts first according to the following criteria,
# in descending order of importance:
# * media pointed to by some dup_media_id;
# * media with a dup_media_id;
# * media whose url domain matches that of the story;
# * media with a lower media_id
sub get_preferred_story
{
    my ( $db, $url, $redirect_url, $stories ) = @_;

    my $media_lookup = {};
    for my $story ( @{ $stories } )
    {
        next if ( $media_lookup->{ $story->{ media_id } } );

        my $medium = $db->find_by_id( 'media', $story->{ media_id } );
        $medium->{ story } = $story;
        $medium->{ dup_target } =
          $db->query( "select 1 from media where dup_media_id = ?", $story->{ media_id } )->hash ? 1 : 0;
        $medium->{ dup_source } = $medium->{ dup_media_id } ? 1 : 0;
        $medium->{ matches_domain } = _story_domain_matches_medium( $db, $medium, $url, $redirect_url );

        $media_lookup->{ $medium->{ media_id } } = $medium;
    }

    my $media = [ values %{ $media_lookup } ];

    sub _compare_media
    {
             ( $b->{ dup_target } <=> $a->{ dup_target } )
          || ( $b->{ dup_source } <=> $a->{ dup_source } )
          || ( $b->{ matches_domain } <=> $a->{ matches_domain } )
          || ( $a->{ media_id } <=> $b->{ media_id } );
    }

    my $sorted_media = [ sort _compare_media @{ $media } ];

    return $sorted_media->[ 0 ]->{ story };
}

sub story_has_download_text
{
    my ( $db, $story ) = @_;

    my $dt = $db->query( <<SQL, $story->{ stories_id } )->hash;
select 1 from download_texts dt join downloads d on ( dt.downloads_id = d.downloads_id ) where d.stories_id = ?
SQL

    return $dt ? 1 : 0;
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

    # look for matching stories, ignore those in foreign_rss_links media
    my $stories = $db->query( <<'END', $u, $ru, $nu, $nru )->hashes;
select s.* from stories s
        join media m on s.media_id = m.media_id
    where ( s.url in ( $1 , $2, $3, $4 ) or s.guid in ( $1, $2, $3, $4 ) ) and
        m.foreign_rss_links = false
END

    # we have to do a separate query here b/c postgres was not coming
    # up with a sane query plan for the combined query
    my $seed_stories = $db->query( <<'END', $u, $ru, $nu, $nru )->hashes;
select s.* from stories s
        join media m on s.media_id = m.media_id
        join controversy_seed_urls csu on s.stories_id = csu.stories_id
    where ( csu.url in ( $1, $2, $3, $4 ) ) and
        m.foreign_rss_links = false
END

    my $story = get_preferred_story( $db, $u, $ru, [ @{ $stories }, @{ $seed_stories } ] );

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
            map { extract_download( $db, $_ ) } @{ $downloads };
        }
        else
        {
            die( "Unknown extract_policy: '$extract_policy'" );
        }
    }

    return $story;
}

# return true if the story is already in controversy_stories
sub story_is_controversy_story
{
    my ( $db, $controversy, $story ) = @_;

    my ( $is_old ) = $db->query(
        "select 1 from controversy_stories where stories_id = ? and controversies_id = ?",
        $story->{ stories_id },
        $controversy->{ controversies_id }
    )->flat;

    print STDERR "EXISTING CONTROVERSY STORY: $story->{ url }\n" if ( $is_old );

    return $is_old;
}

# get the redirect url for the link, add it to the hash, and save it in the db
sub add_redirect_url_to_link
{
    my ( $db, $link ) = @_;

    $link->{ redirect_url } = MediaWords::Util::Web::get_cached_link_download_redirect_url( $link );
    $db->query(
        "update controversy_links set redirect_url = ? where controversy_links_id = ?",
        encode( 'utf8', $link->{ redirect_url } ),
        $link->{ controversy_links_id }
    );
}

# if the ref_stories_id for the controversy_link story and controversy does not
# exist, set ref_stories_id the controversy_link to the ref_story.  If it already
# exists, delete the link
sub set_controversy_ref_story
{
    my ( $db, $ref_story, $controversy_link ) = @_;

    my $ref_stories_id   = $ref_story->{ stories_id };
    my $stories_id       = $controversy_link->{ stories_id };
    my $controversies_id = $controversy_link->{ controversies_id };

    my $link_exists = $db->query( <<END, $ref_stories_id, $stories_id, $controversies_id )->hash;
select 1 from controversy_links
    where ref_stories_id = ? and stories_id = ? and controversies_id = ?
END

    if ( $link_exists )
    {
        $db->query( <<END, $controversy_link->{ controversy_links_id } );
delete from controversy_links where controversy_links_id = ?
END
    }
    else
    {
        $db->query( <<END, $ref_story->{ stories_id }, $controversy_link->{ controversy_links_id } );
update controversy_links set ref_stories_id = ? where controversy_links_id = ?
END
    }
}

sub set_controversy_link_ref_story
{
    my ( $db, $story, $controversy_link ) = @_;

    return unless ( $controversy_link->{ controversy_links_id } );

    my $link_exists = $db->query( <<END, $story->{ stories_id }, $controversy_link->{ controversy_links_id } )->hash;
select 1
    from controversy_links a,
        controversy_links b
    where
        a.stories_id = b.stories_id and
        a.controversies_id = b.controversies_id and
        a.ref_stories_id = ? and
        b.controversy_links_id = ?
END

    if ( $link_exists )
    {
        $db->delete_by_id( 'controversy_links', $controversy_link->{ controversy_links_id } );
    }
    else
    {
        $db->query( <<END, $story->{ stories_id }, $controversy_link->{ controversy_links_id } );
update controversy_links set ref_stories_id = ? where controversy_links_id = ?
END
        $controversy_link->{ ref_stories_id } = $story->{ stories_id };
    }
}

# return true if this story is already a controversy story or
# if the story should be skipped for being a self linked story (see skup_self_linked_story())
sub skip_controversy_story
{
    my ( $db, $controversy, $story, $link ) = @_;

    return 1 if ( story_is_controversy_story( $db, $controversy, $story ) );

    my $spidered_tag = get_spidered_tag( $db );

    # never do a self linked story skip for stories that were not spidered
    return 0 unless ( $db->query( <<END, $story->{ stories_id }, $spidered_tag->{ tags_id } )->hash );
select 1 from stories_tags_map where stories_id = ? and tags_id = ?
END

    my $ss = $db->find_by_id( 'stories', $link->{ stories_id } );
    return 0 if ( $ss->{ media_id } && ( $ss->{ media_id } != $story->{ media_id } ) );

    return 1 if ( _skip_self_linked_domain( $db, $link ) );

    my $cid = $controversy->{ controversies_id };

    # this query is much quicker than the below one, so do it first
    my ( $num_stories ) = $db->query( <<END, $cid, $story->{ media_id }, $spidered_tag->{ tags_id } )->flat;
select count(*)
    from cd.live_stories s
        join stories_tags_map stm on ( s.stories_id = stm.stories_id )
    where
        s.controversies_id = ? and
        s.media_id = ? and
        stm.tags_id = ?
END

    return 0 if ( $num_stories <= $MAX_SELF_LINKED_STORIES );

    my ( $num_cross_linked_stories ) = $db->query( <<END, $cid, $story->{ media_id }, $spidered_tag->{ tags_id } )->flat;
select count( distinct rs.stories_id )
    from cd.live_stories rs
        join controversy_links cl on ( cl.controversies_id = \$1 and rs.stories_id = cl.ref_stories_id )
        join cd.live_stories ss on ( ss.controversies_id = \$1 and cl.stories_id = ss.stories_id )
        join stories_tags_map sstm on ( sstm.stories_id = ss.stories_id )
        join stories_tags_map rstm on ( rstm.stories_id = rs.stories_id )
    where
        rs.controversies_id = \$1 and
        rs.media_id = \$2 and
        ss.media_id <> rs.media_id and
        sstm.tags_id = \$3 and
        rstm.tags_id = \$3
    limit ( $num_stories - $MAX_SELF_LINKED_STORIES )
END

    my ( $num_unlinked_stories ) = $db->query( <<END, $cid, $story->{ media_id } )->flat;
select count( distinct rs.stories_id )
from cd.live_stories rs
    left join controversy_links cl on ( cl.controversies_id = \$1 and rs.stories_id = cl.ref_stories_id )
where
    rs.controversies_id = \$1 and
    rs.media_id = \$2 and
    cl.ref_stories_id is null
limit ( $num_stories - $MAX_SELF_LINKED_STORIES )
END

    my $num_self_linked_stories = $num_stories - $num_cross_linked_stories - $num_unlinked_stories;

    if ( $num_self_linked_stories > $MAX_SELF_LINKED_STORIES )
    {
        say STDERR "SKIP SELF LINKED STORY: $story->{ url } [$num_self_linked_stories]";

        my $medium_domain = MediaWords::Util::URL::get_url_domain( $link->{ url } );
        $_skip_self_linked_domain->{ $medium_domain } = 1;

        return 1;
    }

    return 0;
}

# if the story matches the controversy pattern, add it to controversy_stories and controversy_links
sub add_to_controversy_stories_and_links_if_match
{
    my ( $db, $controversy, $story, $link ) = @_;

    set_controversy_link_ref_story( $db, $story, $link ) if ( $link->{ controversy_links_id } );

    return if ( skip_controversy_story( $db, $controversy, $story, $link ) );

    if ( $link->{ assume_match } || story_matches_controversy_pattern( $db, $controversy, $story ) )
    {
        print STDERR "CONTROVERSY MATCH: $link->{ url }\n";
        $link->{ iteration } ||= 0;
        add_to_controversy_stories_and_links( $db, $controversy, $story, $link->{ iteration } + 1 );
    }

}

# return true if the domain of the linked url is the same
# as the domain of the linking story and either the domain is in
# $_skip_self_linked_domain or the linked url is a /tag or /category page
sub _skip_self_linked_domain
{
    my ( $db, $link ) = @_;

    my $domain = MediaWords::Util::URL::get_url_domain( $link->{ url } );

    return 0 unless ( $_skip_self_linked_domain->{ $domain } || ( $link->{ url } =~ /\/(tag|category|author|search)/ ) );

    return 0 unless ( $link->{ stories_id } );

    # only skip if the media source of the linking story is the same as the media
    # source of the linked story.  we can't know the media source of the linked story
    # without adding it first, though, which we want to skip because it's time
    # expensive to do so.  so we just compare the url domain as a proxy for
    # media source instead.
    my $source_story = $db->find_by_id( 'stories', $link->{ stories_id } );

    my $source_domain = MediaWords::Util::URL::get_url_domain( $source_story->{ url } );

    if ( $source_domain eq $domain )
    {
        print STDERR "SKIP SELF LINKED DOMAIN: $domain\n";
        return 1;
    }

    return 0;
}

# check whether each link has a matching story already in db.  if so, add
# that story to the controversy if it matches, otherwise add the link to the
# list of links to fetch.  return the list of links to fetch.
sub add_links_with_matching_stories
{
    my ( $db, $controversy, $new_links ) = @_;

    # find all the links that we can find existing stories for without having to fetch anything
    my $fetch_links     = [];
    my $extract_stories = [];
    for my $link ( @{ $new_links } )
    {
        next if ( $link->{ ref_stories_id } );

        print STDERR "spidering $link->{ url } ...\n";

        next if ( _skip_self_linked_domain( $db, $link ) );

        if ( my $story = get_matching_story_from_db( $db, $link, 'defer' ) )
        {
            push( @{ $extract_stories }, $story );
            $link->{ story } = $story;
            $story->{ link } = $link;
        }
        else
        {
            print STDERR "add to fetch list ...\n";
            push( @{ $fetch_links }, $link );
        }
    }

    extract_stories( $db, $extract_stories );

    map { add_to_controversy_stories_if_match( $db, $controversy, $_, $_->{ link } ) } @{ $extract_stories };

    mine_controversy_stories( $db, $controversy );

    return $fetch_links;
}

# given the list of links, add any stories that might match the controversy (by matching against url
# and raw html) and return that list of stories, none of which have been extracted
sub get_stories_to_extract
{
    my ( $db, $controversy, $fetch_links ) = @_;

    MediaWords::Util::Web::cache_link_downloads( $fetch_links );

    my $extract_stories = [];

    for my $link ( @{ $fetch_links } )
    {
        next if ( $link->{ ref_stories_id } );

        print STDERR "fetch spidering $link->{ url } ...\n";

        next if ( _skip_self_linked_domain( $db, $link ) );

        add_redirect_url_to_link( $db, $link );
        my $story = get_matching_story_from_db( $db, $link, 'defer' );

        say STDERR "FOUND MATCHING STORY" if ( $story );

        $story ||= add_new_story( $db, $link, undef, $controversy, 0, 1, 1 );

        if ( $story )
        {
            $link->{ story } = $story;
            $story->{ link } = $link;
            push( @{ $extract_stories }, $story );
        }

        $db->commit;
    }

    return $extract_stories;

}

# extract the stories in parallel by forking off extraction processes up $max_processes at a time
sub extract_stories
{
    my ( $db, $stories ) = @_;

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };
    my $unique_stories = [ values( %{ $stories_lookup } ) ];

    say STDERR "EXTRACT_STORIES: " . scalar( @{ $unique_stories } );

    my $max_processes = 16;

    my $pm = new Parallel::ForkManager( $max_processes );

    for my $story ( @{ $unique_stories } )
    {
        $pm->start and next;

        $db = MediaWords::DB::reset_forked_db( $db );

        $db->dbh->{ AutoCommit } = 0;

        if ( !story_has_download_text( $db, $story ) )
        {
            my $download = $db->query( <<SQL, $story->{ stories_id } )->hash;
select * from downloads where stories_id = ? order by downloads_id asc limit 1
SQL
            extract_download( $db, $download );
        }

        $db->commit;

        $pm->finish;
    }

    $pm->wait_all_children;
}

# download any unmatched link in new_links, add it as a story, extract it, add any links to the controversy_links list.
# each hash within new_links can either be a controversy_links hash or simply a hash with a { url } field.  if
# the link is a controversy_links hash, the controversy_link will be updated in the database to point ref_stories_id
# to the new link story.  For each link, set the { story } field to the story found or created for the link.
sub add_new_links
{
    my ( $db, $controversy, $iteration, $new_links ) = @_;

    $db->dbh->{ AutoCommit } = 0;

    my $trimmed_links = [];
    for my $link ( @{ $new_links } )
    {
        my $skip_link = url_failed_potential_match( $link->{ url } )
          || url_failed_potential_match( $link->{ redirect_url } );
        if ( $skip_link )
        {
            say STDERR "ALREADY SKIPPED LINK: $link->{ url }";
        }
        else
        {
            push( @{ $trimmed_links }, $link );
        }
    }

    my $fetch_links = add_links_with_matching_stories( $db, $controversy, $new_links );

    my $extract_stories = get_stories_to_extract( $db, $controversy, $fetch_links );

    extract_stories( $db, $extract_stories );

    map { add_to_controversy_stories_if_match( $db, $controversy, $_, $_->{ link } ) } @{ $extract_stories };

    mine_controversy_stories( $db, $controversy );

    # delete any links that were skipped for whatever reason
    for my $link ( @{ $new_links } )
    {
        if ( !$link->{ ref_stories_id } && $link->{ controversy_links_id } )
        {
            # ref_stories_id is null to make sure we don't delete a valid link
            $db->query( <<END, $link->{ controversy_links_id } );
delete from controversy_links where controversy_links_id = ? and ref_stories_id is null
END
        }
    }
    $db->commit;

    $db->dbh->{ AutoCommit } = 1;
}

# build a lookup table of aliases for a url based on url and redirect_url fields in the
# controversy_links
sub get_url_alias_lookup
{
    my ( $db ) = @_;

    my $lookup;

    my $url_pairs = $db->query( <<END )->hashes;
select distinct url, redirect_url from
    ( ( select url, redirect_url from controversy_links where url <> redirect_url ) union
      ( select s.url, cs.redirect_url
           from controversy_stories cs join stories s on ( cs.stories_id = s.stories_id )
           where cs.redirect_url <> s.url
       ) ) q
END

    # use a hash of hashes so that we can do easy hash lookups in the
    # network traversal below
    for my $url_pair ( @{ $url_pairs } )
    {
        $lookup->{ $url_pair->{ url } }->{ $url_pair->{ redirect_url } } = 1;
        $lookup->{ $url_pair->{ redirect_url } }->{ $url_pair->{ url } } = 1;
    }

    # traverse the network gathering indirect aliases
    my $lookups_updated = 1;
    while ( $lookups_updated )
    {
        $lookups_updated = 0;
        while ( my ( $url, $aliases ) = each( %{ $lookup } ) )
        {
            for my $alias_url ( keys( %{ $aliases } ) )
            {
                if ( !$lookup->{ $alias_url }->{ $url } )
                {
                    $lookups_updated = 1;
                    $lookup->{ $alias_url }->{ $url } = 1;
                }
            }
        }
    }

    my $url_alias_lookup = {};
    while ( my ( $url, $aliases ) = each( %{ $lookup } ) )
    {
        $url_alias_lookup->{ $url } = [ keys( %{ $aliases } ) ];
    }

    return $url_alias_lookup;
}

# return true if the domain of the source story medium url is found in the target story url
sub medium_domain_matches_url
{
    my ( $db, $source_story, $target_story ) = @_;

    my $source_medium = $db->query( "select url from media where media_id = ?", $source_story->{ media_id } )->hash;

    my $domain = MediaWords::DBI::Media::get_medium_domain( $source_medium );

    return 1 if ( index( lc( $target_story->{ url } ), lc( $domain ) ) >= 0 );

    return 0;
}

# for each stories in aggregator stories that has the same url as a controversy story, add
# that story as a controversy story with a link to the matching controversy story
sub add_outgoing_foreign_rss_links
{
    my ( $db, $controversy ) = @_;

    # I can't get postgres to generate a plan that recognizes that
    # these aggregator url matches are pretty rare, so it's quicker
    # to do the url lookups in perl
    my $target_stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select s.* from stories s, controversy_stories cs
    where s.stories_id = cs.stories_id and cs.controversies_id = ?
END

    my $url_alias_lookup = get_url_alias_lookup( $db );
    for my $target_story ( @{ $target_stories } )
    {
        my $urls = $url_alias_lookup->{ $target_story->{ url } };
        push( @{ $urls }, $target_story->{ url } );
        my $url_params = join( ',', map { '?' } ( 1 .. scalar( @{ $urls } ) ) );
        my $source_stories = $db->query( <<END, @{ $urls } )->hashes;
select s.*
    from stories s
        join media m on ( s.media_id = m.media_id )
    where
        m.foreign_rss_links and
        s.url in ( $url_params ) and
        not exists (
            select 1 from controversy_stories cs where s.stories_id = cs.stories_id )
END
        for my $source_story ( @{ $source_stories } )
        {
            next if ( medium_domain_matches_url( $db, $source_story, $target_story ) );

            add_to_controversy_stories( $db, $controversy, $source_story, 1, 1, 1 );
            $db->create(
                "controversy_links",
                {
                    stories_id       => $source_story->{ stories_id },
                    url              => encode( 'utf8', $target_story->{ url } ),
                    controversies_id => $controversy->{ controversies_id },
                    ref_stories_id   => $target_story->{ stories_id },
                    link_spidered    => 1,
                }
            );
        }
    }
}

# find any links for the controversy of this iteration or less that have not already been spidered
# and call add_new_links on them.
sub spider_new_links
{
    my ( $db, $controversy, $iteration ) = @_;

    my $new_links = $db->query( <<END, $iteration, $controversy->{ controversies_id } )->hashes;
select distinct cs.iteration, cl.* from controversy_links cl, controversy_stories cs
    where
        cl.ref_stories_id is null and
        cl.stories_id = cs.stories_id and
        ( cs.iteration < \$1 or cs.iteration = 1000 ) and
        cs.controversies_id = \$2 and
        cl.controversies_id = \$2
END

    # do this in chunks so that we don't have recheck lots of links for matches when we
    # restart the mining process in the middle
    my $chunk_size = 2000;
    for ( my $i = 0 ; $i < scalar( @{ $new_links } ) ; $i += $chunk_size )
    {
        my $end = List::Util::min( $i + $chunk_size - 1, $#{ $new_links } );
        add_new_links( $db, $controversy, $iteration, [ @{ $new_links }[ $i .. $end ] ] );
    }
}

# run the spider over any new links, for $num_iterations iterations
sub run_spider
{
    my ( $db, $controversy ) = @_;

    my $num_iterations = $controversy->{ max_iterations };

    for my $i ( 1 .. $num_iterations )
    {
        spider_new_links( $db, $controversy, $i );
    }
}

# make sure every controversy story has a redirect url, even if it is just the original url
sub add_redirect_urls_to_controversy_stories
{
    my ( $db, $controversy ) = @_;

    my $stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select distinct s.*
    from cd.live_stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id and s.controversies_id = cs.controversies_id )
    where cs.redirect_url is null and cs.controversies_id = ?
END

    add_redirect_links( $db, $stories );
    for my $story ( @{ $stories } )
    {
        $db->query(
            "update controversy_stories set redirect_url = ? where stories_id = ? and controversies_id = ?",
            $story->{ redirect_url },
            $story->{ stories_id },
            $controversy->{ controversies_id }
        );
    }
}

# mine for links any stories in controversy_stories for this controversy that have not already been mined
sub mine_controversy_stories
{
    my ( $db, $controversy ) = @_;

    my $stories = $db->query( <<SQL, $controversy->{ controversies_id } )->hashes;
select distinct s.*, cs.link_mined, cs.redirect_url
    from cd.live_stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id and s.controversies_id = cs.controversies_id )
    where
        cs.link_mined = false and
        cs.controversies_id = ?
    order by s.publish_date
SQL
    generate_controversy_links( $db, $controversy, $stories );
}

# reset the "controversy_< name >:all" tag to point to all stories in controversy_stories
sub update_controversy_tags
{
    my ( $db, $controversy ) = @_;

    my $tagset_name = "controversy_" . $controversy->{ name };

    my $all_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "$tagset_name:all" )
      || die( "Can't find or create all_tag" );

    $db->query( <<END, $all_tag->{ tags_id }, $controversy->{ controversies_id } );
delete from stories_tags_map stm
    where stm.tags_id = ? and
        not exists ( select 1 from controversy_stories cs
                         where cs.controversies_id = ? and cs.stories_id = stm.stories_id )
END

    $db->query(
        "insert into stories_tags_map ( stories_id, tags_id ) " .
          "  select distinct stories_id, $all_tag->{ tags_id } from controversy_stories " .
          "    where controversies_id = ? and " .
          "      stories_id not in ( select stories_id from stories_tags_map where tags_id = ? )",
        $controversy->{ controversies_id },
        $all_tag->{ tags_id }
    );

    my $q_tagset_name = $db->dbh->quote( $tagset_name );
    $db->query(
        "delete from stories_tags_map stm using tags t, tag_sets ts " .
          "  where stm.tags_id = t.tags_id and t.tag_sets_id = ts.tag_sets_id and " .
          "    ts.name = $q_tagset_name and not exists " .
          "      ( select 1 from controversy_stories cs where cs.controversies_id = ? and cs.stories_id = stm.stories_id )",
        $controversy->{ controversies_id }
    );
}

# increase the link_weight of each story to which this story links and recurse along links from those stories.
# the link_weight gets increment by ( 1 / path_depth ) so that stories further down along the link path
# get a smaller increment than more direct links.
sub add_link_weights
{
    my ( $story, $stories_lookup, $path_depth, $link_path_lookup ) = @_;

    $story->{ link_weight } += ( 1 / $path_depth ) if ( !$path_depth );

    return if ( !scalar( @{ $story->{ links } } ) );

    $link_path_lookup->{ $story->{ stories_id } } = 1;

    for my $link ( @{ $story->{ links } } )
    {
        next if ( $link_path_lookup->{ $link->{ ref_stories_id } } );

        my $linked_story = $stories_lookup->{ $link->{ ref_stories_id } };
        add_link_weights( $linked_story, $stories_lookup, $path_depth++, $link_path_lookup );
    }
}

# get stories with a { source_stories } field that is a list
# of links to stories linking to that story
sub get_stories_with_sources
{
    my ( $db, $controversy ) = @_;

    my $links = $db->query( "select * from controversy_links_cross_media where controversies_id = ?",
        $controversy->{ controversies_id } )->hashes;
    my $stories = $db->query(
        "select s.* from controversy_stories cs, stories s " .
          "  where s.stories_id = cs.stories_id and cs.controversies_id = ?",
        $controversy->{ controversies_id }
    )->hashes;

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    for my $link ( @{ $links } )
    {
        my $ref_story = $stories_lookup->{ $link->{ ref_stories_id } };
        push( @{ $ref_story->{ source_stories } }, $stories_lookup->{ $link->{ stories_id } } );
    }

    return $stories;
}

# generate a link weight score for each cross media controversy_link
# by adding a point for each incoming link, then adding the some of the
# link weights of each link source divided by the ( iteration * 10 ) of the recursive
# weighting (so the first reweighting run will add 1/10 the weight of the sources,
# the second 1/20 of the weight of the sources, and so on)
sub generate_link_weights
{
    my ( $db, $controversy, $stories ) = @_;

    map { $_->{ source_stories } ||= []; } @{ $stories };
    map { $_->{ link_weight } = scalar( @{ $_->{ source_stories } } ) } @{ $stories };

    for my $i ( 1 .. $LINK_WEIGHT_ITERATIONS )
    {
        for my $story ( @{ $stories } )
        {
            map { $story->{ link_weight } += ( $_->{ link_weight } / ( $i * 10 ) ) } @{ $story->{ source_stories } };
        }
    }

    for my $story ( @{ $stories } )
    {
        $db->query(
            "update controversy_stories set link_weight = ? where stories_id = ? and controversies_id = ?",
            $story->{ link_weight } || 0,
            $story->{ stories_id },
            $controversy->{ controversies_id }
        );
    }
}

# get the smaller iteration of the two stories
sub get_merged_iteration
{
    my ( $db, $controversy, $delete_story, $keep_story ) = @_;

    my $cid = $controversy->{ controversies_id };
    my $i = $db->query( <<END, $cid, $delete_story->{ stories_id }, $keep_story->{ stories_id } )->flat;
select iteration
    from controversy_stories
    where
        controversies_id  = \$1 and
        stories_id in ( \$2, \$3 )
END

    return List::Util::min( @{ $i } );
}

# merge delete_story into keep_story by making sure all links that are in delete_story are also in keep_story
# and making sure that keep_story is in controversy_stories.  once done, delete delete_story from controversy_stories (but not
# from stories)
sub merge_dup_story
{
    my ( $db, $controversy, $delete_story, $keep_story ) = @_;

    print STDERR <<END;
dup $keep_story->{ title } [ $keep_story->{ stories_id } ] <- $delete_story->{ title } [ $delete_story->{ stories_id } ]
END

    die( "refusing to merge identical story" ) if ( $delete_story->{ stories_id } == $keep_story->{ stories_id } );

    my $controversies_id = $controversy->{ controversies_id };

    my $ref_controversy_links = $db->query( <<END, $delete_story->{ stories_id }, $controversies_id )->hashes;
select * from controversy_links where ref_stories_id = ? and controversies_id = ?
END

    for my $ref_controversy_link ( @{ $ref_controversy_links } )
    {
        set_controversy_link_ref_story( $db, $keep_story, $ref_controversy_link );
    }

    if ( !story_is_controversy_story( $db, $controversy, $keep_story ) )
    {
        my $merged_iteration = get_merged_iteration( $db, $controversy, $delete_story, $keep_story );
        add_to_controversy_stories( $db, $controversy, $keep_story, $merged_iteration, 1 );
    }

    $db->begin;

    my $controversy_links = $db->query( <<END, $delete_story->{ stories_id }, $controversies_id )->hashes;
select * from controversy_links where stories_id = ? and controversies_id = ?
END

    for my $controversy_link ( @{ $controversy_links } )
    {
        my ( $link_exists ) =
          $db->query( <<END, $keep_story->{ stories_id }, $controversy_link->{ ref_stories_id }, $controversies_id )->hash;
select * from controversy_links where stories_id = ? and ref_stories_id = ? and controversies_id = ?
END

        if ( !$link_exists )
        {
            $db->query( <<END, $keep_story->{ stories_id }, $controversy_link->{ controversy_links_id } );
update controversy_links set stories_id = ? where controversy_links_id = ?
END
        }
    }

    $db->query( <<END, $delete_story->{ stories_id }, $controversies_id );
delete from controversy_stories where stories_id = ? and controversies_id = ?
END

    $db->query( <<END, $delete_story->{ stories_id }, $keep_story->{ stories_id } );
insert into controversy_merged_stories_map ( source_stories_id, target_stories_id ) values ( ?, ? )
END

    $db->commit;

}

# if the given story's url domain does not match the url domain of the story,
# merge the story into another medium
sub merge_foreign_rss_story
{
    my ( $db, $controversy, $story ) = @_;

    my $medium = get_cached_medium_by_id( $db, $story->{ media_id } );

    my $medium_domain = MediaWords::DBI::Media::get_medium_domain( $medium );

    # for stories in ycombinator.com, allow stories with a http://yombinator.com/.* url
    return if ( index( lc( $story->{ url } ), lc( $medium_domain ) ) >= 0 );

    my $link = { url => $story->{ url } };

    # note that get_matching_story_from_db will not return $story b/c it now checkes for foreign_rss_links = true
    my $merge_into_story = get_matching_story_from_db( $db, $link )
      || add_new_story( $db, undef, $story, $controversy );

    merge_dup_story( $db, $controversy, $story, $merge_into_story );
}

# find all controversy stories with a foreign_rss_links medium and merge each story
# into a different medium unless the story's url domain matches that of the existing
# medium.
sub merge_foreign_rss_stories
{
    my ( $db, $controversy ) = @_;

    my $foreign_stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select s.* from stories s, controversy_stories cs, media m
    where s.stories_id = cs.stories_id and s.media_id = m.media_id and
        m.foreign_rss_links = true and cs.controversies_id = ? and
        not cs.valid_foreign_rss_story
END

    map { merge_foreign_rss_story( $db, $controversy, $_ ) } @{ $foreign_stories };
}

# clone the given story, assigning the new media_id and copying over the download, extracted text, and so on
sub clone_story
{
    my ( $db, $controversy, $old_story, $new_medium ) = @_;

    my $story = {
        url          => encode( 'utf8', $old_story->{ url } ),
        media_id     => $new_medium->{ media_id },
        guid         => encode( 'utf8', $old_story->{ guid } ),
        publish_date => $old_story->{ publish_date },
        collect_date => MediaWords::Util::SQL::sql_now,
        description  => encode( 'utf8', $old_story->{ description } ),
        title        => encode( 'utf8', $old_story->{ title } )
    };

    $story = safely_create_story( $db, $story );
    add_to_controversy_stories( $db, $controversy, $story, 0, 1 );

    $db->query( <<SQL, $story->{ stories_id }, $old_story->{ stories_id } );
insert into stories_tags_map ( stories_id, tags_id )
    select \$1, stm.tags_id from stories_tags_map stm where stm.stories_id = \$2
SQL

    my $feed = get_spider_feed( $db, $new_medium );
    $db->create( 'feeds_stories_map', { feeds_id => $feed->{ feeds_id }, stories_id => $story->{ stories_id } } );

    my $download = create_download_for_new_story( $db, $story, $feed );

    my $content = get_first_download_content( $db, $old_story );

    MediaWords::DBI::Downloads::store_content_determinedly( $db, $download, $content );

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

# given a story in archive_is, find the destination domain and merge into the associated medium
sub merge_archive_is_story
{
    my ( $db, $controversy, $story ) = @_;

    my $original_url = MediaWords::Util::Web::get_original_url_from_momento_archive_url( $story->{ url } );

    if ( !$original_url )
    {
        say STDERR "could not get original URL for $story->{ url } SKIPPING";
        return;
    }

    say STDERR "Archive: $story->{ url }, Original $original_url";
    my $link_medium = get_spider_medium( $db, $original_url );

    my $new_story = $db->query(
        <<END, $link_medium->{ media_id }, $original_url, $story->{ guid }, $story->{ title }, $story->{ publish_date } )->hash;
SELECT s.* FROM stories s
    WHERE s.media_id = \$1 and
        ( ( \$2 in ( s.url, s.guid ) ) or
          ( \$3 in ( s.url, s.guid ) ) or
          ( s.title = \$4 and date_trunc( 'day', s.publish_date ) = \$5 ) )
END

    $new_story ||= clone_story( $db, $controversy, $story, $link_medium );

    merge_dup_story( $db, $controversy, $story, $new_story );
}

# merge all stories belonging to the 'archive.is' medium into the linked domain media
sub merge_archive_is_stories
{
    my ( $db, $controversy ) = @_;

    my $archive_is_stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
SELECT distinct s.*
    FROM cd.live_stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id and s.controversies_id = cs.controversies_id )
        join media m on ( s.media_id = m.media_id )
    WHERE
        cs.controversies_id = ? and
        m.name = 'is';

END

    print STDERR "merging " . scalar( @{ $archive_is_stories } ) . " archive.is stories\n"
      if ( scalar( @{ $archive_is_stories } ) );

    map { merge_archive_is_story( $db, $controversy, $_ ) } @{ $archive_is_stories };
}

# given a story in a dup_media_id medium, look for or create a story in the medium pointed to by dup_media_id
sub merge_dup_media_story
{
    my ( $db, $controversy, $story ) = @_;

    # allow foreign_rss_links get get_dup_medium, because at this point the only
    # foreign_rss_links stories should have been added by add_outgoing_foreign_rss_links
    my $dup_medium = get_dup_medium( $db, $story->{ media_id }, 1 );

    print STDERR "no dup medium found\n" unless ( $dup_medium );

    return unless ( $dup_medium );

    my $new_story = $db->query(
        <<END, $dup_medium->{ media_id }, $story->{ url }, $story->{ guid }, $story->{ title }, $story->{ publish_date } )->hash;
SELECT s.* FROM stories s
    WHERE s.media_id = \$1 and
        ( ( \$2 in ( s.url, s.guid ) ) or
          ( \$3 in ( s.url, s.guid ) ) or
          ( s.title = \$4 and date_trunc( 'day', s.publish_date ) = \$5 ) )
END

    $new_story ||= clone_story( $db, $controversy, $story, $dup_medium );

    merge_dup_story( $db, $controversy, $story, $new_story );
}

# mark delete_medium as a dup of keep_medium and merge
# all stories from all controversies in delete_medium into
# keep_medium
sub merge_dup_medium_all_controversies
{
    my ( $db, $delete_medium, $keep_medium ) = @_;

    $db->query( <<END, $keep_medium->{ media_id }, $delete_medium->{ media_id } );
update media set dup_media_id = ? where media_id = ?
END

    my $stories = $db->query( <<END, $delete_medium->{ media_id } )->hashes;
SELECT distinct s.*, cs.controversies_id
    FROM stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id )
    WHERE
        s.media_id = ?
END

    my $controversies_map = {};
    my $controversies     = $db->query( "select * from controversies" )->hashes;
    map { $controversies_map->{ $_->{ controversies_id } } = $_ } @{ $controversies };

    for my $story ( @{ $stories } )
    {
        my $controversy = $controversies_map->{ $story->{ controversies_id } };
        merge_dup_media_story( $db, $controversy, $story );
    }
}

# merge all stories belonging to dup_media_id media to the dup_media_id in the current controversy
sub merge_dup_media_stories
{
    my ( $db, $controversy ) = @_;

    my $dup_media_stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
SELECT distinct s.*
    FROM cd.live_stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id and s.controversies_id = cs.controversies_id )
        join media m on ( s.media_id = m.media_id )
    WHERE
        m.dup_media_id is not null and
        cs.controversies_id = ?
END

    print STDERR "merging " . scalar( @{ $dup_media_stories } ) . " stories\n" if ( scalar( @{ $dup_media_stories } ) );

    map { merge_dup_media_story( $db, $controversy, $_ ) } @{ $dup_media_stories };
}

# import all controversy_seed_urls that have not already been processed
sub import_seed_urls
{
    my ( $db, $controversy ) = @_;

    my $controversies_id = $controversy->{ controversies_id };

    # take care of any seed urls with urls that we have already processed
    # for this controversy
    $db->query( <<END, $controversies_id );
update controversy_seed_urls a set stories_id = b.stories_id, processed = 't'
    from controversy_seed_urls b
    where a.url = b.url and
        a.controversies_id = ? and b.controversies_id = a.controversies_id and
        a.stories_id is null and b.stories_id is not null
END

    my $seed_urls = $db->query( <<END, $controversies_id )->hashes;
select * from controversy_seed_urls where controversies_id = ? and processed = 'f'
END

    my $non_content_urls = [];
    for my $csu ( @{ $seed_urls } )
    {
        if ( $csu->{ content } )
        {
            my $story = get_matching_story_from_db( $db, $csu )
              || add_new_story( $db, $csu, undef, $controversy, 0, 1 );
            add_to_controversy_stories_if_match( $db, $controversy, $story, $csu );
        }
        else
        {
            push( @{ $non_content_urls }, $csu );
        }
    }

    add_new_links( $db, $controversy, 0, $non_content_urls );

    $db->dbh->{ AutoCommit } = 0;
    for my $seed_url ( @{ $seed_urls } )
    {
        $db->query( <<END, $seed_url->{ story }->{ stories_id }, $seed_url->{ controversy_seed_urls_id } );
update controversy_seed_urls set stories_id = ?, processed = 't' where controversy_seed_urls_id = ?
END
    }
    $db->commit;
    $db->dbh->{ AutoCommit } = 1;

}

# look for any stories in the controversy tagged with a date method of 'current_time' and
# assign each the earliest source link date if any source links exist
sub add_source_link_dates
{
    my ( $db, $controversy ) = @_;

    my $stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select s.* from stories s, controversy_stories cs, tag_sets ts, tags t, stories_tags_map stm
    where s.stories_id = cs.stories_id and cs.controversies_id = ? and
        stm.stories_id = s.stories_id and stm.tags_id = t.tags_id and
        t.tag_sets_id = ts.tag_sets_id and
        t.tag in ( 'current_time' ) and ts.name = 'date_guess_method'
END

    for my $story ( @{ $stories } )
    {
        my $source_link = $db->query( <<END, $controversy->{ controversies_id } )->hash;
select cl.*, s.publish_date from controversy_links cl, cd.live_stories s
    where cl.ref_stories_id = s.stories_id and cl.controversies_id = s.controversies_id
    order by ( cl.controversies_id = ? ) asc, s.publish_date asc
END

        next unless ( $source_link );

        $db->query( <<END, $source_link->{ publish_date }, $controversy->{ controversies_id } );
update stories set publish_date = ? where stories_id = ?
END
        MediaWords::DBI::Stories::GuessDate::assign_date_guess_method( $db, $story, 'source_link' );
    }
}

# make a pass through all broken stories caching any broken downloads
# using MediaWords::Util::Web::cache_link_downloads.  these will get
# fetched with Web::get_cached_link_download and then stored via
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

    MediaWords::Util::Web::cache_link_downloads( $fetch_links );
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

    die( "can't find any pick element in reference list" );
}

# add the medium url to the controversy_ignore_redirects table
sub add_medium_url_to_ignore_redirects
{
    my ( $db, $medium ) = @_;

    my $url = MediaWords::Util::URL::normalize_url_lossy( $medium->{ url } );

    my $ir = $db->query( "select * from controversy_ignore_redirects where url = ?", $url )->hash;

    return if ( $ir );

    $db->create( 'controversy_ignore_redirects', { url => $url } );
}

# add to controversy stories if the story is not already in the controversy and it
# assume_match is true or the story matches the controversy pattern
sub add_to_controversy_stories_if_match
{
    my ( $db, $controversy, $story, $link, $assume_match ) = @_;

    set_controversy_link_ref_story( $db, $story, $link ) if ( $link->{ controversy_links_id } );

    return if ( skip_controversy_story( $db, $controversy, $story, $link ) );

    if ( $assume_match || $link->{ assume_match } || story_matches_controversy_pattern( $db, $controversy, $story ) )
    {
        print STDERR "CONTROVERSY MATCH: $link->{ url }\n";
        $link->{ iteration } ||= 0;
        add_to_controversy_stories( $db, $controversy, $story, $link->{ iteration } + 1, 0 );
    }
}

# get the field pointing to the stories table from
# one of the below controversy url tables
sub get_story_field_from_url_table
{
    my ( $table ) = @_;

    my $story_field;
    if ( $table eq 'controversy_links' )
    {
        $story_field = 'ref_stories_id';
    }
    elsif ( $table eq 'controversy_seed_urls' )
    {
        $story_field = 'stories_id';
    }
    else
    {
        die( "Unknown table: '$table'" );
    }

    return $story_field;
}

# get lookup hash with the normalized url as the key for the
# the controversy_links or controversy_seed_urls associated with the
# given story and controversy
sub get_redirect_url_lookup
{
    my ( $db, $story, $controversy, $table ) = @_;

    my $story_field = get_story_field_from_url_table( $table );

    my $rows = $db->query( <<END, $story->{ stories_id }, $controversy->{ controversies_id } )->hashes;
select a.* from ${ table } a where ${ story_field } = ? and controversies_id = ?
END
    my $lookup = {};
    map { push( @{ $lookup->{ MediaWords::Util::URL::normalize_url_lossy( $_->{ url } ) } }, $_ ) } @{ $rows };

    return $lookup;
}

# set the given controversy_links or controversy_seed_urls to point to the given story
sub unredirect_story_url
{
    my ( $db, $story, $url, $lookup, $table ) = @_;

    my $story_field = get_story_field_from_url_table( $table );

    my $nu = MediaWords::Util::URL::normalize_url_lossy( $url->{ url } );

    for my $row ( @{ $lookup->{ $nu } } )
    {
        print STDERR "unredirect url: $row->{ url }, $table, $story->{ stories_id }\n";
        $db->query( <<END, $story->{ stories_id }, $row->{ "${ table }_id" } );
update ${ table } set ${ story_field } = ? where ${ table }_id = ?
END
    }
}

# reprocess the urls that redirected into the given story.
# $urls should be a list of hashes with the following fields:
# url, assume_match, manual_redirect
# if assume_match is true, assume that the story created from the
# url matches the controversy.  If manual_redirect is set, manually
# set the redirect_url to the value (for manually inputting redirects
# for dead links).
sub unredirect_story
{
    my ( $db, $controversy, $story, $urls ) = @_;

    for my $u ( grep { $_->{ manual_redirect } } @{ $urls } )
    {
        $u->{ redirect_url } = $u->{ manual_redirect };
    }

    MediaWords::Util::Web::cache_link_downloads( $urls );

    my $cl_lookup  = get_redirect_url_lookup( $db, $story, $controversy, 'controversy_links' );
    my $csu_lookup = get_redirect_url_lookup( $db, $story, $controversy, 'controversy_seed_urls' );

    for my $url ( @{ $urls } )
    {
        my $new_story = get_matching_story_from_db( $db, $url )
          || add_new_story( $db, $url, undef, $controversy );

        add_to_controversy_stories_if_match( $db, $controversy, $new_story, $url, $url->{ assume_match } );

        unredirect_story_url( $db, $new_story, $url, $cl_lookup,  'controversy_links' );
        unredirect_story_url( $db, $new_story, $url, $csu_lookup, 'controversy_seed_urls' );

        $db->query( <<END, $story->{ stories_id }, $controversy->{ controversies_id } );
delete from controversy_stories where stories_id = ? and controversies_id = ?
END
    }
}

# a list of all original urls that were redirected to the url for the given story
# along with the controversy in which that url was found, returned as a list
# of hashes with the fields { url, controversies_id, controversy_name }
sub get_story_original_urls
{
    my ( $db, $story ) = @_;

    my $urls = $db->query( <<'END', $story->{ stories_id } )->hashes;
select q.url, q.controversies_id, c.name controversy_name
    from
        (
            select distinct controversies_id, url from controversy_links where ref_stories_id = $1
            union
            select controversies_id, url from controversy_seed_urls where stories_id = $1
         ) q
         join controversies c on ( c.controversies_id = q.controversies_id )
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
    my ( $db, $controversy, $stories ) = @_;

    my $stories_ids_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $story_sentence_counts = $db->query( <<END )->hashes;
select stories_id, count(*) sentence_count from story_sentences where stories_id in ($stories_ids_list) group by stories_id
END

    my $ssc = {};
    map { $ssc->{ $_->{ stories_id } } = 0 } @{ $stories };
    map { $ssc->{ $_->{ stories_id } } = $_->{ sentence_count } } @{ $story_sentence_counts };

    $stories = [ sort { $ssc->{ $b->{ stories_id } } <=> $ssc->{ $a->{ stories_id } } } @{ $stories } ];

    my $keep_story = shift( @{ $stories } );

    print "duplicates:\n";
    print "\t$keep_story->{ title } [$keep_story->{ url } $keep_story->{ stories_id }]\n";
    map { print "\t$_->{ title } [$_->{ url } $_->{ stories_id }]\n" } @{ $stories };

    print "\n";

    map { merge_dup_story( $db, $controversy, $_, $keep_story ) } @{ $stories };

}

# return hash of { $media_id => $stories } for the controversy
sub get_controversy_stories_by_medium
{
    my ( $db, $controversy ) = @_;

    my $stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select s.stories_id, s.media_id, s.title, s.url
    from cd.live_stories s
    where s.controversies_id = ?
END

    my $media_lookup = {};
    map { push( @{ $media_lookup->{ $_->{ media_id } } }, $_ ) } @{ $stories };

    return $media_lookup;
}

# look for duplicate stories within each media source and merge any duplicates into the
# story with the shortest title
sub find_and_merge_dup_stories
{
    my ( $db, $controversy ) = @_;

    for my $get_dup_stories (
        \&MediaWords::DBI::Stories::get_medium_dup_stories_by_url,
        \&MediaWords::DBI::Stories::get_medium_dup_stories_by_title
      )
    {
        # regenerate story list each time to capture previously merged stories
        my $media_lookup = get_controversy_stories_by_medium( $db, $controversy );

        while ( my ( $media_id, $stories ) = each( %{ $media_lookup } ) )
        {
            my $dup_stories = $get_dup_stories->( $db, $stories );
            map { merge_dup_stories( $db, $controversy, $_ ) } @{ $dup_stories };
        }
    }
}

# import stories intro controversy_seed_urls from solr by running
# controversy->{ solr_seed_query } against solr.  if the solr query has
# already been imported, do nothing.
sub import_solr_seed_query
{
    my ( $db, $controversy ) = @_;

    return if ( $controversy->{ solr_seed_query_run } );

    print STDERR "executing solr query: $controversy->{ solr_seed_query }\n";
    my $stories = MediaWords::Solr::search_for_stories( $db, { q => $controversy->{ solr_seed_query }, rows => 100000 } );

    print STDERR "adding " . scalar( @{ $stories } ) . " stories to controversy_seed_urls\n";

    $db->begin;

    for my $story ( @{ $stories } )
    {
        my $csu = {
            controversies_id => $controversy->{ controversies_id },
            url              => $story->{ url },
            stories_id       => $story->{ stories_id },
            assume_match     => 'f'
        };

        $db->create( 'controversy_seed_urls', $csu );
    }

    $db->query( "update controversies set solr_seed_query_run = 't' where controversies_id = ?",
        $controversy->{ controversies_id } );

    $db->commit;
}

# mine the given controversy for links and to recursively discover new stories on the web.
# options:
#   import_only - only run import_seed_urls and import_solr_seed and exit
#   cache_broken_downloads - speed up fixing broken downloads, but add time if there are no broken downloads
#   skip_outgoing_foreign_rss_links - skip slow process of adding links from foreign_rss_links media
sub mine_controversy ($$;$)
{
    my ( $db, $controversy, $options ) = @_;

    # Log activity that's about to start
    MediaWords::DBI::Activities::log_system_activity( $db, 'cm_mine_controversy', $controversy->{ controversies_id },
        $options )
      || die( "Unable to log the 'cm_mine_controversy' activity." );

    say STDERR "importing solr seed query ...";
    import_solr_seed_query( $db, $controversy );

    say STDERR "importing seed urls ...";
    import_seed_urls( $db, $controversy );

    say STDERR "mining controversy stories ...";
    mine_controversy_stories( $db, $controversy );

    # # merge dup media and stories here to avoid redundant link processing for imported urls
    say STDERR "merging media_dup stories ...";
    merge_dup_media_stories( $db, $controversy );

    say STDERR "merging dup stories ...";
    find_and_merge_dup_stories( $db, $controversy );

    unless ( $options->{ import_only } )
    {
        say STDERR "merging foreign_rss stories ...";
        merge_foreign_rss_stories( $db, $controversy );

        say STDERR "adding redirect urls to controversy stories ...";
        add_redirect_urls_to_controversy_stories( $db, $controversy );

        say STDERR "mining controversy stories ...";
        mine_controversy_stories( $db, $controversy );

        say STDERR "running spider ...";
        run_spider( $db, $controversy );

        # disabling because there are too many foreign_rss_links media sources
        # with bogus feeds that pollute the results
        # if ( !$options->{ skip_outgoing_foreign_rss_links } )
        # {
        #     say STDERR "adding outgoing foreign rss links ...";
        #     add_outgoing_foreign_rss_links( $db, $controversy );
        # }

        say STDERR "merging archive_is stories ...";
        merge_archive_is_stories( $db, $controversy );

        # merge dup media and stories again to catch dups from spidering
        say STDERR "merging media_dup stories ...";
        merge_dup_media_stories( $db, $controversy );

        say STDERR "merging dup stories ...";
        find_and_merge_dup_stories( $db, $controversy );

        say STDERR "adding source link dates ...";
        add_source_link_dates( $db, $controversy );

        say STDERR "updating story_tags ...";
        update_controversy_tags( $db, $controversy );

        # my $stories = get_stories_with_sources( $db, $controversy );

        # say STDERR "generating link weights ...";
        # generate_link_weights( $db, $controversy, $stories );

        # say STDERR "generating link text similarities ...";
        # generate_link_text_similarities( $db, $stories );

        say STDERR "analyzing controversy tables...";
        $db->query( "analyze controversy_stories" );
        $db->query( "analyze controversy_links" );
    }

    if ( $controversy->{ process_with_bitly } )
    {
        unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
        {
            die "Bit.ly processing is not enabled.";
        }

        say STDERR "enqueueing all (new) stories for Bit.ly processing ...";

        # For the sake of simplicity, just re-enqueue all controversy's stories for
        # Bit.ly processing. The ones that are already processed (have a respective
        # record in the raw key-value database) will be skipped, and the new
        # ones will be enqueued further for fetching Bit.ly stats.
        my $args = { controversies_id => $controversy->{ controversies_id } };
        MediaWords::GearmanFunction::Bitly::EnqueueAllControversyStories->enqueue_on_gearman( $args );
    }
}

1;
