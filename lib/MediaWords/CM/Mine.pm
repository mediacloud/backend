package MediaWords::CM::Mine;

# Mine through stories found for the given controversy and find all the links in each story.
# Find each link, try to find whether it matches any given story.  If it doesn't, create a
# new story.  Add that story's links to the queue if it matches the pattern for the
# controversy.  Write the resulting stories and links to controversy_stories and controversy_links.

use strict;

use Carp;
use Data::Dumper;
use DateTime;
use Encode;
use Getopt::Long;
use HTML::LinkExtractor;
use URI;
use URI::Escape;

use MediaWords::CM::GuessDate;
use MediaWords::CM::GuessDate::Result;
use MediaWords::DBI::Media;
use MediaWords::DBI::Stories;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

# number of times to iterate through spider
use constant NUM_SPIDER_ITERATIONS => 15;

# number of times to run through the recursive link weight process
use constant LINK_WEIGHT_ITERATIONS => 3;

# tag that will be associate with all controversy_stories at the end of the script
use constant ALL_TAG => 'all';

# ignore links that match this pattern
my $_ignore_link_pattern =
  '(www.addtoany.com)|(novostimira.com)|(ads\.pheedo)|(www.dailykos.com\/user)|' .
  '(livejournal.com\/(tag|profile))|(sfbayview.com\/tag)|(absoluteastronomy.com)|' .
  '(\/share.*http)|(digg.com\/submit)|(facebook.com.*mediacontentsharebutton)|' .
  '(feeds.wordpress.com\/.*\/go)|(sharetodiaspora.github.io\/)';

# cache of media by media id
my $_media_cache = {};

# cache for spidered:spidered tag
my $_spidered_tag;

# cache of media by sanitized url
my $_media_url_lookup;

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

# return a list of all links that appear in the html
sub get_links_from_html
{
    my ( $html ) = @_;

    my $link_extractor = new HTML::LinkExtractor();

    $link_extractor->parse( \$html );

    my $links = [];
    for my $link ( @{ $link_extractor->links } )
    {
        next if ( !$link->{ href } );

        next if ( $link->{ href } !~ /^http/i );

        next if ( $link->{ href } =~ $_ignore_link_pattern );

        $link =~ s/www-nc.nytimes/www.nytimes/i;

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

    return get_links_from_html( $content );
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
        MediaWords::DBI::Stories::fix_story_downloads_if_needed( $db, $story );
        $extracted_html = MediaWords::DBI::Stories::get_extracted_html_from_db( $db, $story );
    }

    return $extracted_html;
}

# find any links in the extracted html or the description of the story.
sub get_links_from_story
{
    my ( $db, $story ) = @_;

    print STDERR "mining $story->{ title } [$story->{ url }] ...\n";

    my $extracted_html = get_extracted_html( $db, $story );
    my $links = get_links_from_html( $extracted_html );

    my $more_links = [];
    if ( story_media_has_full_text_rss( $db, $story ) )
    {
        $more_links = get_links_from_html( $story->{ description } );
    }
    elsif ( $story->{ media_id } == 1720 )
    {
        $more_links = get_boingboing_links( $db, $story );
    }

    return $links if ( !@{ $more_links } );

    my $link_lookup = {};
    map { $link_lookup->{ MediaWords::Util::URL::normalize_url( $_->{ url } ) } = 1 } @{ $links };
    for my $more_link ( @{ $more_links } )
    {
        next if ( $link_lookup->{ MediaWords::Util::URL::normalize_url( $more_link->{ url } ) } );
        push( @{ $links }, $more_link );
    }

    # add_redirect_links( $links ) if ( @{ $links } );

    return $links;
}

# for each story, return a list of the links found in either the extracted html or the story description
sub generate_controversy_links
{
    my ( $db, $controversy, $stories ) = @_;

    for my $story ( @{ $stories } )
    {
        my $links = get_links_from_story( $db, $story );

        #print STDERR "links found:\n" . join( "\n", map { "  ->" . $_->{ url } } @{ $links } ) . "\n";
        # print Dumper( $links );

        for my $link ( @{ $links } )
        {
            my $link_exists = $db->query(
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

        $db->query(
            "update controversy_stories set link_mined = true where stories_id = ? and controversies_id = ?",
            $story->{ stories_id },
            $controversy->{ controversies_id }
        );
    }
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

    if ( !$_media_url_lookup->{ MediaWords::Util::URL::normalize_url( $url ) } )
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
            $_media_url_lookup->{ MediaWords::Util::URL::normalize_url( $medium->{ url } ) } = $medium;
        }
    }

    return $_media_url_lookup->{ MediaWords::Util::URL::normalize_url( $url ) };
}

# add medium to media_url_lookup
sub add_medium_to_url_lookup
{
    my ( $medium ) = @_;

    $_media_url_lookup->{ MediaWords::Util::URL::normalize_url( $medium->{ url } ) } = $medium;
}

# derive the url and a media source name from the given story's url
sub generate_medium_url_and_name_from_url
{
    my ( $story_url ) = @_;

    my $normalized_url = MediaWords::Util::URL::normalize_url( $story_url );

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

    $medium = get_dup_medium( $db, $medium->{ dup_media_id } ) if ( $medium && $medium->{ dup_media_id } );

    return $medium if ( $medium );

    # avoid conflicts with existing media urls that are missed by the above query b/c of dups feeds or foreign_rss_links
    $medium_url = substr( $medium_url, 0, 1000 ) . '#spider';

    $medium = {
        name        => encode( 'utf8', substr( $medium_name, 0, 128 ) ),
        url         => encode( 'utf8', $medium_url ),
        moderated   => 't',
        feeds_added => 't'
    };

    $medium = $db->create( 'media', $medium );

    print STDERR "add medium: $medium_name / $medium_url / $medium->{ medium_id }\n";

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

# parse the content for tags that might indicate the story's title
sub get_story_title_from_content
{

    my ( $content, $url ) = @_;

    my $title;

    if ( $content =~ m~<meta property=\"og:title\" content=\"([^\"]+)\"~si )
    {
        $title = $1;
    }
    elsif ( $content =~ m~<meta property=\"og:title\" content=\'([^\']+)\'~si )
    {
        $title = $1;
    }
    elsif ( $content =~ m~<title>([^<]+)</title>~si )
    {
        $title = $1;
    }
    else
    {
        $title = $url;
    }

    if ( length( $title ) > 1024 )
    {
        $title = substr( $title, 0, 1024 );
    }

    return $title;
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

    eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "controversy", 1, 1, 1 ); };
    warn "extract error processing download $download->{ downloads_id }" if ( $@ );
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

    my $source_story;
    if ( $source_link && $source_link->{ stories_id } )
    {
        $source_story = $db->find_by_id( 'stories', $source_link->{ stories_id } );
        $story->{ publish_date } = $source_story->{ publish_date };
    }

    my $date = MediaWords::CM::GuessDate::guess_date( $db, $story, $story_content, 1 );
    if ( $date->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
    {
        return ( $date->{ guess_method }, $date->{ date } );
    }
    elsif ( $date->{ result } eq MediaWords::CM::GuessDate::Result::INAPPLICABLE )
    {
        return ( 'undateable', $source_story ? $source_story->{ publish_date } : DateTime->now->datetime );
    }

    return ( 'current_time', DateTime->now->datetime );
}
my $reliable_methods = [ qw(guess_by_url guess_by_url_and_date_text merged_story_rss manual) ];

# recursively search for the medium pointed to by dup_media_id
# by the media_id medium.  return the first medium that does not have a dup_media_id.
sub get_dup_medium
{
    my ( $db, $media_id, $count ) = @_;

    croak( "loop detected" ) if ( $count > 10 );

    return undef unless ( $media_id );

    my $medium = get_cached_medium_by_id( $db, $media_id );

    if ( $medium->{ dup_media_id } )
    {
        return get_dup_medium( $db, $medium->{ dup_media_id }, ++$count );
    }

    return undef if ( $medium->{ foreign_rss_links } );

    return $medium;
}

# return true if we should ignore redirects to the target media source, usually
# to avoid redirects to domainresellers for previously valid and important but now dead
# links
sub ignore_redirect
{
    my ( $db, $link ) = @_;

    print STDERR "ignore_redirect\n";
    return 0 unless ( $link->{ redirect_url } && ( $link->{ redirect_url } ne $link->{ url } ) );

    my ( $medium_url, $medium_name ) = generate_medium_url_and_name_from_url( $link->{ redirect_url } );

    my $u = MediaWords::Util::URL::normalize_url( $medium_url );
    print STDERR "$u\n";

    my $match = $db->query( "select 1 from controversy_ignore_redirects where url = ?", $u )->hash;

    print STDERR "ignore_redirect: $match\n";
    return $match ? 1 : 0;
}

# generate a new story hash from the story content, an existing story, a link, and a medium.
# includes guessing the publish date.  return the story and the date guess method
sub generate_new_story_hash
{
    my ( $db, $story_content, $old_story, $link, $medium ) = @_;

    my $story = {
        url          => $old_story->{ url },
        guid         => $old_story->{ url },
        media_id     => $medium->{ media_id },
        collect_date => DateTime->now->datetime,
        title        => encode( 'utf8', $old_story->{ title } ),
        description  => ''
    };

    my ( $date_guess_method, $publish_date ) = get_new_story_date( $db, $story, $story_content, $old_story, $link );
    print STDERR "date guess: $date_guess_method: $publish_date\n";

    $story->{ publish_date } = $publish_date;

    return ( $story, $date_guess_method );
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
        feeds_id      => $feed->{ feeds_id },
        stories_id    => $story->{ stories_id },
        url           => $story->{ url },
        host          => lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] ),
        type          => 'content',
        sequence      => 1,
        state         => 'success',
        path          => 'content:pending',
        priority      => 1,
        download_time => DateTime->now->datetime,
        extracted     => 't'
    };

    $download = $db->create( 'downloads', $download );

    return $download;
}

# add a new story and download corresponding to the given link or existing story
sub add_new_story
{
    my ( $db, $link, $old_story, $controversy ) = @_;

    die( "only one of $link or $old_story should be set" ) if ( $link && $old_story );

    my $story_content;
    if ( $link )
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
            $old_story->{ title } = get_story_title_from_content( $story_content, $old_story->{ url } );
        }
    }
    else
    {

        # make sure content exists in case content is missing from the existing story
        MediaWords::DBI::Stories::fix_story_downloads_if_needed( $db, $old_story );
        $story_content = ${ MediaWords::DBI::Stories::fetch_content( $db, $old_story ) };
    }

    print STDERR "add_new_story: $old_story->{ url }\n";

    $old_story->{ url } = substr( $old_story->{ url }, 0, 1024 );

    my $medium = get_dup_medium( $db, $old_story->{ media_id } ) || get_spider_medium( $db, $old_story->{ url } );
    my $feed = get_spider_feed( $db, $medium );

    my ( $story, $date_guess_method ) = generate_new_story_hash( $db, $story_content, $old_story, $link, $medium );

    if ( my $dup_story = get_dup_story( $db, $story ) )
    {
        return $dup_story;
    }

    my $story = safely_create_story( $db, $story );

    my $spidered_tag = get_spidered_tag( $db );
    $db->create( 'stories_tags_map', { stories_id => $story->{ stories_id }, tags_id => $spidered_tag->{ tags_id } } );

    MediaWords::DBI::Stories::assign_date_guess_method( $db, $story, $date_guess_method );

    print STDERR "add story: $story->{ title } / $story->{ url } / $story->{ publish_date } / $story->{ stories_id }\n";

    $db->create( 'feeds_stories_map', { feeds_id => $feed->{ feeds_id }, stories_id => $story->{ stories_id } } );

    my $download = create_download_for_new_story( $db, $story, $feed );

    MediaWords::DBI::Downloads::store_content_determinedly( $db, $download, $story_content );

    extract_download( $db, $download );

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
    my ( $db, $story, $query_story_search ) = @_;

    my $dt = $db->query( <<END, $story->{ stories_id }, $query_story_search->{ query_story_searches_id } )->hash;
select 1 
    from download_texts dt 
        join downloads d on ( dt.downloads_id = d.downloads_id )
        join query_story_searches qss on ( qss.query_story_searches_id = \$2 )
    where 
        d.stories_id = \$1 and
        dt.download_text ~* qss.pattern
    limit 1
END
    return $dt ? 1 : 0;
}

# return true if any of the story_sentences with no duplicates for the story matches the controversy search pattern
sub story_sentence_matches_pattern
{
    my ( $db, $story, $query_story_search ) = @_;

    my $ss = $db->query( <<END, $story->{ stories_id }, $query_story_search->{ query_story_searches_id } )->hash;
select 1 
    from story_sentences ss
        join story_sentence_counts ssc 
            on ( ss.stories_id = ssc.first_stories_id and ss.sentence_number = ssc.first_sentence_number )
        join query_story_searches qss on ( qss.query_story_searches_id = \$2 )
    where 
        ss.stories_id = \$1 and
        ss.sentence ~* qss.pattern and
        ssc.sentence_count < 2
    limit 1
END

    return $ss ? 1 : 0;
}

# return the type of match if the story title, url, description, or sentences match controversy search pattern.
sub story_matches_controversy_pattern
{
    my ( $db, $controversy, $story, $metadata_only ) = @_;

    my $query_story_search = $db->find_by_id( 'query_story_searches', $controversy->{ query_story_searches_id } );

    my $perl_re = $query_story_search->{ pattern };

    # translate from postgres to perl regex
    $perl_re =~ s/\[\[\:[\<\>]\:\]\]/[^a-z]/g;
    for my $field ( qw/title description url redirect_url/ )
    {
        return $field if ( $story->{ $field } =~ /$perl_re/is );
    }

    return 0 if ( $metadata_only );

    # check for download_texts match first because some stories don't have
    # story_sentences, and it is expensive to generate the missing story_sentences
    return 0 unless ( story_download_text_matches_pattern( $db, $story, $query_story_search ) );

    MediaWords::DBI::Stories::add_missing_story_sentences( $db, $story );

    return story_sentence_matches_pattern( $db, $story, $query_story_search ) ? 'sentence' : 0;
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

# check for stories with the same title within a week of the given story in the same or duplicate media source.
# return all duplicates stories found.
sub get_dup_stories
{
    my ( $db, $story, $controversy ) = @_;

    return [] if ( length( $story->{ title } ) < 16 );

    my $query = <<END;
select distinct s.* from stories s, controversy_stories cs
    where cs.stories_id = s.stories_id and s.title = ? and s.stories_id <> ? and 
        s.media_id = ? and cs.controversies_id = ?    
END

    my $possible_dup_stories = $db->query(
        $query,
        $story->{ title },
        $story->{ stories_id } || -1,
        $story->{ media_id },
        $controversy->{ controversies_id }
    )->hashes;

    my $dup_stories = [];
    for my $dup_story ( @{ $possible_dup_stories } )
    {
        my $dup_story_epoch = MediaWords::Util::SQL::get_epoch_from_sql_date( $dup_story->{ publish_date } );
        my $story_epoch     = MediaWords::Util::SQL::get_epoch_from_sql_date( $story->{ publish_date } );

        # if the stories aren't within a week, be more careful about matching
        if (   ( $dup_story_epoch >= ( $story_epoch - ( 7 * 86400 ) ) )
            && ( $dup_story_epoch <= ( $story_epoch + ( 7 * 86400 ) ) ) )
        {
            push( @{ $dup_stories }, $dup_story );
            next;
        }

        # if the stories aren't in the same week, require that the length be greater than 32
        next if ( length( $story->{ title } ) < 32 );

        # and require that the urls match minus parameters
        my $dup_story_url_no_p = $dup_story->{ url };
        my $story_url_no_p     = $story->{ url };
        $dup_story_url_no_p =~ s/(.*)\?(.*)/$1/;
        $story_url_no_p =~ s/(.*)\?(.*)/$1/;

        next if ( lc( $dup_story_url_no_p ) ne lc( $story_url_no_p ) );

        push( @{ $dup_stories }, $dup_story );
    }

    return $dup_stories;
}

# check for stories with the same title within a week of the given story in the same or duplicate media source.
# return all duplicates stories found.
sub get_dup_story
{
    my ( $db, $story, $controversy ) = @_;

    my $dup_stories = get_dup_stories( $db, $story, $controversy );

    return @{ $dup_stories } ? $dup_stories->[ 0 ] : undef;
}

# look for a story matching the link url in the db
sub get_matching_story_from_db
{
    my ( $db, $link, $controversy ) = @_;

    my $u = substr( $link->{ url }, 0, 1024 );

    my $ru;
    if ( !ignore_redirect( $db, $link ) )
    {
        $ru = substr( $link->{ redirect_url }, 0, 1024 ) || $u;
    }

    # look for matching stories, ignore those in foreign_rss_links media and those
    # in dup_media_id media.
    my $story = $db->query( <<'END', $u, $ru )->hash;
select s.* from stories s
        join media m on s.media_id = m.media_id
    where ( s.url in ( $1 , $2 ) or s.guid in ( $1, $2 ) ) and 
        m.foreign_rss_links = false and m.dup_media_id is null
END

    # we have to do a separate query here b/c postgres was not coming
    # up with a sane query plan for the combined query
    $story ||= $db->query( <<'END', $u, $ru )->hash;
select s.* from stories s
        join media m on s.media_id = m.media_id
        join controversy_seed_urls csu on s.stories_id = csu.stories_id
    where ( csu.url in ( $1, $2 ) ) and 
        m.foreign_rss_links = false and m.dup_media_id is null
END

    # replace with dup story if there's one already added to controversy_stories
    $story = get_dup_story( $db, $story, $controversy ) || $story;

    if ( $story )
    {
        my $downloads = $db->query( "select * from downloads where stories_id = ? and extracted = 'f' order by downloads_id",
            $story->{ stories_id } )->hashes;
        map { extract_download( $db, $_ ) } @{ $downloads };
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

    print STDERR "EXISTING CONTROVERSY STORY\n" if ( $is_old );

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
    my ( $db, $ref_story, $controversy_link ) - @_;

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
select 1 from controversy_links a, controversy_links b
    where a.stories_id = b.stories_id and a.controversies_id = b.controversies_id and
        a.ref_stories_id = ? and b.controversy_links_id = ?
END

    return if ( $link_exists );

    croak( "story $story->{ stories_id } does not exist" )
      unless ( $db->find_by_id( 'stories', $story->{ stories_id } ) );

    $db->query( <<END, $story->{ stories_id }, $controversy_link->{ controversy_links_id } );
update controversy_links set ref_stories_id = ? where controversy_links_id = ?
END

}

# if the story matches the controversy pattern, add it to controversy_stories and controversy_links
sub add_to_controversy_stories_and_links_if_match
{
    my ( $db, $controversy, $story, $link ) = @_;

    set_controversy_link_ref_story( $db, $story, $link ) if ( $link->{ controversy_links_id } );

    return if ( story_is_controversy_story( $db, $controversy, $story ) );

    if ( $link->{ assume_match } || story_matches_controversy_pattern( $db, $controversy, $story ) )
    {
        print STDERR "CONTROVERSY MATCH: $link->{ url }\n";
        add_to_controversy_stories_and_links( $db, $controversy, $story, $link->{ iteration } + 1 );
    }

}

# download any unmatched link in new_links, add it as a story, extract it, add any links to the controversy_links list.
# each hash within new_links can either be a controversy_links hash or simply a hash with a { url } field.  if
# the link is a controversy_links hash, the controversy_link will be updated in the database to point ref_stories_id
# to the new link story.  For each link, set the { story } field to the story found or created for the link.
sub add_new_links
{
    my ( $db, $controversy, $iteration, $new_links ) = @_;

    # find all the links that we can find existing stories for without having to fetch anything
    my $fetch_links = [];
    for my $link ( @{ $new_links } )
    {
        next if ( $link->{ ref_stories_id } );

        print STDERR "spidering $link->{ url } ...\n";

        if ( my $story = get_matching_story_from_db( $db, $link, $controversy ) )
        {
            add_to_controversy_stories_and_links_if_match( $db, $controversy, $story, $link );
            $link->{ story } = $story;
        }
        else
        {
            push( @{ $fetch_links }, $link );
        }
    }

    MediaWords::Util::Web::cache_link_downloads( $fetch_links );

    for my $link ( @{ $fetch_links } )
    {
        next if ( $link->{ ref_stories_id } );

        print STDERR "fetch spidering $link->{ url } ...\n";

        add_redirect_url_to_link( $db, $link );
        my $story = get_matching_story_from_db( $db, $link, $controversy )
          || add_new_story( $db, $link, undef, $controversy );

        $link->{ story } = $story;

        add_to_controversy_stories_and_links_if_match( $db, $controversy, $story, $link );
    }
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
select s.* from stories s, media m
    where m.foreign_rss_links and s.media_id = m.media_id and s.url in ( $url_params ) and
        not exists ( select 1 from controversy_stories cs where s.stories_id = cs.stories_id )
        
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

    my $new_links = $db->query(
        "select distinct cs.iteration, cl.* from controversy_links cl, controversy_stories cs " .
          "  where cl.ref_stories_id is null and cl.stories_id = cs.stories_id and cs.iteration < ? and " .
          "    cs.controversies_id = ? and cl.controversies_id = ? ",
        $iteration,
        $controversy->{ controversies_id },
        $controversy->{ controversies_id }
    )->hashes;

    add_new_links( $db, $controversy, $iteration, $new_links );
}

# run the spider over any new links, for $num_iterations iterations
sub run_spider
{
    my ( $db, $controversy, $num_iterations ) = @_;

    for my $i ( 1 .. $num_iterations )
    {
        spider_new_links( $db, $controversy, $i );
    }
}

# make sure every controversy story has a redirect url, even if it is just the original url
sub add_redirect_urls_to_controversy_stories
{
    my ( $db, $controversy ) = @_;

    my $stories = $db->query(
        "select distinct s.* from stories s, controversy_stories cs " .
          "  where s.stories_id = cs.stories_id and cs.redirect_url is null and cs.controversies_id = ?",
        $controversy->{ controversies_id }
    )->hashes;

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

    my $stories = $db->query(
        "select distinct s.*, cs.link_mined, cs.redirect_url from stories s, controversy_stories cs " .
          "  where s.stories_id = cs.stories_id and cs.link_mined = 'f' and cs.controversies_id = ? " .
          "  order by s.publish_date",
        $controversy->{ controversies_id }
    )->hashes;

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

    return if ( !@{ $story->{ links } } );

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

# for each cross media controversy link, add a text similarity score that is the cos sim
# of the text of the source and ref stories.  assumes the $stories argument comes
# with each story with a { source_stories } field that includes all of the source
# stories for that ref story
sub generate_link_text_similarities
{
    my ( $db, $controversy, $stories ) = @_;

    for my $story ( @{ $stories } )
    {
        for my $source_story ( @{ $story->{ source_stories } } )
        {
            my $has_sim = $db->query(
                "select 1 from controversy_links " .
                  "  where stories_id = ? and ref_stories_id = ? and text_similarity > 0 and controversies_id = ?",
                $source_story->{ stories_id },
                $story->{ stories_id },
                $controversy->{ controversies_id }
            )->list;
            next if ( $has_sim );

            MediaWords::DBI::Stories::add_word_vectors( $db, [ $story, $source_story ], 1 );
            MediaWords::DBI::Stories::add_cos_similarities( $db, [ $story, $source_story ] );

            my $sim = $story->{ similarities }->[ 1 ];

            print STDERR "link sim:\n\t$story->{ title } [ $story->{ stories_id } ]\n" .
              "\t$source_story->{ title } [ $source_story->{ stories_id } ]\n\t$sim\n\n";

            $db->query(
                "update controversy_links set text_similarity = ? " .
                  "  where stories_id = ? and ref_stories_id = ? and controversies_id = ?",
                $sim,
                $source_story->{ stories_id },
                $story->{ stories_id },
                $controversy->{ controversies_id }
            );

            map { $_->{ similarities } = undef } ( $story, $source_story );
        }
    }
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
    map { $_->{ link_weight } = @{ $_->{ source_stories } } } @{ $stories };

    for my $i ( 1 .. LINK_WEIGHT_ITERATIONS )
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

    add_to_controversy_stories( $db, $controversy, $keep_story, 1000, 1 )
      unless ( story_is_controversy_story( $db, $controversy, $keep_story ) );

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
    my $merge_into_story = get_matching_story_from_db( $db, $link, $controversy )
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

# given a story in a dup_media_id medium, look for or create a story in the medium pointed to by dup_media_id
sub merge_dup_media_story
{
    my ( $db, $controversy, $story ) = @_;

    my $dup_medium = get_dup_medium( $db, $story->{ media_id } );

    return unless ( $dup_medium );

    my $new_story =
      $db->query( <<END, $dup_medium->{ media_id }, $story->{ url }, $story->{ title }, $story->{ publish_date } )->hash;
SELECT s.* FROM stories s 
    WHERE s.media_id = ? and
        ( ( ? in ( s.url, s.guid ) ) or ( s.title = ? and date_trunc( 'day', s.publish_date ) = ? ) )
END

    $new_story ||= add_new_story( $db, undef, $story, $controversy );

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
SELECT distinct s.* FROM stories s, controversy_stories cs, media m
    WHERE s.stories_id = cs.stories_id and m.media_id = s.media_id and 
        m.dup_media_id is not null and cs.controversies_id = ?
END

    print STDERR "merging " . scalar( @{ $dup_media_stories } ) . " stories\n" if ( @{ $dup_media_stories } );

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

    add_new_links( $db, $controversy, 0, $seed_urls );

    for my $seed_url ( @{ $seed_urls } )
    {
        $db->query( <<END, $seed_url->{ story }->{ stories_id }, $seed_url->{ controversy_seed_urls_id } );
update controversy_seed_urls set stories_id = ?, processed = 't' where controversy_seed_urls_id = ?
END
    }

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
select cl.*, s.publish_date from controversy_links cl, stories s 
    where cl.ref_stories_id = s.stories_id
    order by ( controversies_id = ? ) asc, s.publish_date asc
END

        next unless ( $source_link );

        $db->query( <<END, $source_link->{ publish_date }, $controversy->{ controversies_id } );
update stories set publish_date = ? where stories_id = ?
END
        MediaWords::DBI::Stories::assign_date_guess_method( $db, $story, 'source_link' );
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

# import stories from the query_story_searches associated with this controversy
sub import_query_story_search
{
    my ( $db, $controversy, $cache_broken_story_downloads ) = @_;

    my $stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select distinct s.* 
    from stories s
        join query_story_searches_stories_map qsssm on ( qsssm.stories_id = s.stories_id )
        join controversies c on ( qsssm.query_story_searches_id = c.query_story_searches_id )
        left join controversy_query_story_searches_imported_stories_map cm
            on ( cm.stories_id = s.stories_id and cm.controversies_id = c.controversies_id )
    where
        c.controversies_id = ? and
        cm.stories_id is null
END

    if ( $cache_broken_story_downloads )
    {
        print STDERR "caching broken downloads ...\n";
        cache_broken_story_downloads( $db, $stories );
    }

    for my $story ( @{ $stories } )
    {
        $db->query( <<END, $controversy->{ controversies_id }, $story->{ stories_id } );
insert into controversy_query_story_searches_imported_stories_map 
    ( controversies_id, stories_id ) values ( ?, ? );
END

        my $controversy_story_exists = $db->query( <<END, $story->{ stories_id }, $controversy->{ controversies_id } )->hash;
select 1 from controversy_stories where stories_id = ? and controversies_id = ?
END
        next if ( $controversy_story_exists );

        # don't reimport the story if the story has been merged into a story that is already in the controversy
        my $merged_story = $db->query( <<END, $story->{ stories_id }, $controversy->{ controversies_id } )->hash;
select 1 from controversy_merged_stories_map cmsm, controversy_stories cs
    where cmsm.source_stories_id = ? and cmsm.target_stories_id = cs.stories_id and
        cs.controversies_id = ?
END
        next if ( $merged_story );

        add_to_controversy_stories_and_links( $db, $controversy, $story, 0 );
    }
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

# loop through each story, finding the earliest dup story that is earlier in the sort order of
# the above query than the current story.  put that earliest story in the dups hash where
# the key is the stories_id to delete and the value is the story to keep.  before putting each
# keep story in the array, look it up in the existing dups hash
sub get_stories_dups
{
    my ( $db, $controversy, $stories ) = @_;

    my $dups              = {};
    my $processed_stories = {};
    my $i                 = 0;
    my $num_stories       = @{ $stories };

    for my $story ( @{ $stories } )
    {
        print STDERR "$i / $num_stories\n" unless ( ++$i % 100 );

        $processed_stories->{ $story->{ stories_id } } = 1;
        next if ( $dups->{ $story->{ stories_id } } );

        my $dup_stories = get_dup_stories( $db, $story, $controversy );
        next unless ( @{ $dup_stories } );

        my $dup_story = pick_first_matched_story( $stories, $dup_stories );

        next unless ( $processed_stories->{ $dup_story->{ stories_id } } );

        my $earliest_dup_story = $dup_story;
        while ( my $earlier_dup_story = $dups->{ $earliest_dup_story->{ stories_id } } )
        {
            $earliest_dup_story = $earlier_dup_story;
        }

        $dups->{ $story->{ stories_id } } = $earliest_dup_story;
    }

    return $dups;
}

# find any stories in the controversy that are dups according to get_dup_story and
# merge them.  be sure to merge to the best dated / earliest story and to handle recursive
# duplicates.
sub dedup_stories
{
    my ( $db, $controversy ) = @_;

    my $dgm = $db->query( <<END )->hash;
select ts.* from tag_sets ts where name = 'date_guess_method'
END

    print STDERR "dedup_stories: fetching stories...\n";

    # order stories so that stories with reliable dates are first and then stories with earlier publish
    # dates are first because that the order of preference for which dup to keep
    my $stories = $db->query( <<'END', $dgm->{ tag_sets_id }, $controversy->{ controversies_id } )->hashes;
select s.*, 
        ( t.tags_id is null or t.tag in ( 'merged_story_rss', 'guess_by_url_and_date_text', 'guess_by_url' ) ) date_is_reliable
    from stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id )
        left join 
            ( stories_tags_map stm 
                join tags t on ( stm.tags_id = t.tags_id and t.tag_sets_id = $1 ) 
                join controversy_stories csb on ( csb.stories_id = stm.stories_id and csb.controversies_id = $2 ) )
            on ( s.stories_id = stm.stories_id )
    where cs.controversies_id = $2
    order by date_is_reliable desc, s.publish_date asc
END

    print STDERR "dedup_stories: processing stories...\n";

    my $story_dups = get_stories_dups( $db, $controversy, $stories );

    while ( my ( $delete_stories_id, $keep_story ) = each( %{ $story_dups } ) )
    {
        my $delete_story = $db->find_by_id( 'stories', $delete_stories_id );
        merge_dup_story( $db, $controversy, $delete_story, $keep_story );
    }
}

# add the medium url to the controversy_ignore_redirects table
sub add_medium_url_to_ignore_redirects
{
    my ( $db, $medium ) = @_;

    my $url = MediaWords::Util::URL::normalize_url( $medium->{ url } );

    my $ir = $db->query( "select * from controversy_ignore_redirects where url = ?", $url )->hash;

    return if ( $ir );

    $db->create( 'controversy_ignore_redirects', { url => $url } );
}

# add to controversy stories if the story is not already in the controversy and it
# assume_match is true or the story matches the controversy pattern
sub add_to_controversy_stories_if_match
{
    my ( $db, $controversy, $story, $assume_match ) = @_;

    return if ( story_is_controversy_story( $db, $controversy, $story ) );

    return unless ( $assume_match || story_matches_controversy_pattern( $db, $controversy, $story ) );

    add_to_controversy_stories( $db, $controversy, $story, 0, 1 );
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
    map { push( @{ $lookup->{ MediaWords::Util::URL::normalize_url( $_->{ url } ) } }, $_ ) } @{ $rows };

    return $lookup;
}

# set the given controversy_links or controversy_seed_urls to point to the given story
sub unredirect_story_url
{
    my ( $db, $story, $url, $lookup, $table ) = @_;

    my $story_field = get_story_field_from_url_table( $table );

    my $nu = MediaWords::Util::URL::normalize_url( $url->{ url } );

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
        my $new_story = get_matching_story_from_db( $db, $url, $controversy )
          || add_new_story( $db, $url, undef, $controversy );

        add_to_controversy_stories_if_match( $db, $controversy, $new_story, $url->{ assume_match } );

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
        my $nu = MediaWords::Util::URL::normalize_url( $url->{ url } );
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

# mine the given controversy for links and to recursively discover new stories on the web.
# options:
#   dedup_stories - run story deduping on controversy; should only be necessary of deduping algorithm changes
#   import_only - only run import_seed_urls and import_query_story_search and exit
#   cache_broken_downloads - speed up fixing broken downloads, but add time if there are no broken downloads
sub mine_controversy ($$;$)
{
    my ( $db, $controversy, $options ) = @_;

    # Log activity that's about to start
    MediaWords::DBI::Activities::log_system_activity( $db, 'cm_mine_controversy', $controversy->{ controversies_id },
        $options )
      || die( "Unable to log the 'cm_mine_controversy' activity." );

    print STDERR "importing seed urls ...\n";
    import_seed_urls( $db, $controversy );

    print STDERR "importing query stories search ...\n";
    import_query_story_search( $db, $controversy, $options->{ cache_broken_downloads } );

    dedup_stories( $db, $controversy ) if ( $options->{ dedup_stories } );

    return if ( $options->{ import_only } );

    print STDERR "merging foreign_rss stories ...\n";
    merge_foreign_rss_stories( $db, $controversy );

    print STDERR "adding redirect urls to controversy stories ...\n";
    add_redirect_urls_to_controversy_stories( $db, $controversy );

    print STDERR "mining controversy stories ...\n";
    mine_controversy_stories( $db, $controversy );

    print STDERR "running spider ...\n";
    run_spider( $db, $controversy, NUM_SPIDER_ITERATIONS );

    print STDERR "adding outgoing foreign rss links ...\n";
    add_outgoing_foreign_rss_links( $db, $controversy );

    print STDERR "merging media_dup stories ...\n";
    merge_dup_media_stories( $db, $controversy );

    print STDERR "adding source link dates ...\n";
    add_source_link_dates( $db, $controversy );

    print STDERR "updating story_tags ...\n";
    update_controversy_tags( $db, $controversy );

    # my $stories = get_stories_with_sources( $db, $controversy );

    # print STDERR "generating link weights ...\n";
    # generate_link_weights( $db, $controversy, $stories );

    # print STDERR "generating link text similarities ...\n";
    # generate_link_text_similarities( $db, $stories );

    print STDERR "analyzing controversy tables...\n";
    $db->query( "analyze controversy_stories" );
    $db->query( "analyze controversy_links" );
}

1;
