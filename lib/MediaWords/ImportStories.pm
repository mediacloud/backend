package MediaWords::ImportStories;

# Import stories into the database, handling date bounding and story deduping.  This is only
# a template class.  You must use of the sub class such as MediaWords::ImportStories::ScrapeHTML
# or MediaWords::ImportStories::Feedly to import stories from a given source.
#
# The scrape interface is oo and includes the following parameters to new() in addition to specific
# options supported by the sub class.
# * db - db handle
# * media_id - media source to which to add stories
# * max_pages (optional) - max num of pages to scrape by recursively finding urls matching page_url_pattern
# * start_date (optional) - start date of stories to scrape and dedup
# * end_date (optional) - end date of stories to scrape and dedup
# * debug (optional) - print debug messages urls crawled and stories created
# * dry_run (optional) - do everything but actually insert stories into db
#
# After the sub class identifies all story candidates, ImportStories looks for any
# duplicates among the story candidates and the existing stories in the media sources and only adds as stories
# the candidates with out existing duplicate stories.  The duplication check looks for matching normalized urls
# as well as matching title parts (see MediaWords::DBI::Stories::get_medium_dup_stories_by_<title|url>.
#
# Each sub class needs to implement $self->get_new_stories(), which should return a set of story candidates
# for deduplication and date restriction by this super class.

use Moose::Role;

use Carp;
use Data::Dumper;
use Encode;
use List::MoreUtils;
use Parallel::ForkManager;
use URI::Split;

use MediaWords::CM::GuessDate;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Util::HTML;
use MediaWords::Util::SQL;
use MediaWords::Util::Tags;

has 'db'       => ( is => 'rw', isa => 'Ref', required => 1 );
has 'media_id' => ( is => 'rw', isa => 'Int', required => 1 );

has 'debug'   => ( is => 'rw', isa => 'Int', required => 0 );
has 'dry_run' => ( is => 'rw', isa => 'Int', required => 0 );

has 'max_pages' => ( is => 'rw', isa => 'Int', required => 0, default => 10_000 );

has 'start_date' => ( is => 'rw', isa => 'Str', required => 0, default => '1000-01-01' );
has 'end_date'   => ( is => 'rw', isa => 'Str', required => 0, default => '3000-01-01' );

has 'scrape_feed' => ( is => 'rw', isa => 'Ref', required => 0 );

# sub class must implement $self->get_new_stories(), which returns story objects that have not yet
# been inserted into the db
requires 'get_new_stories';

# given the content, generate a story hash
sub generate_story
{
    my ( $self, $content, $url ) = @_;

    my $db = $self->db;

    my $title = MediaWords::Util::HTML::html_title( $content, $url, 1024 );

    my $story = {
        url          => $url,
        guid         => $url,
        media_id     => $self->media_id,
        collect_date => MediaWords::Util::SQL::sql_now,
        title        => encode( 'utf8', $title ),
        description  => '',
        content      => $content
    };

    my $date_guess = MediaWords::CM::GuessDate::guess_date( $db, $story, $content, 1 );
    if ( $date_guess->{ result } eq $MediaWords::CM::GuessDate::Result::FOUND )
    {
        $story->{ publish_date } = $date_guess->{ date };
    }
    else
    {
        $story->{ publish_date } = MediaWords::Util::SQL::sql_now();
    }

    $story->{ content } = $content;

    return $story;
}

# return true if the publish date is before $self->end_date and after $self->start_date
sub story_is_in_date_range
{
    my ( $self, $publish_date ) = @_;

    my $publish_day = substr( $publish_date, 0, 10 );

    return 0 if ( $self->end_date && ( $publish_day gt $self->end_date ) );

    return 0 if ( $self->start_date && ( $publish_day lt $self->start_date ) );

    return 1;
}

sub _get_stories_in_date_range
{
    my ( $self, $stories ) = @_;

    my $dated_stories = [];
    for my $story ( @{ $stories } )
    {
        push( @{ $dated_stories }, $story ) if ( $self->story_is_in_date_range( $story->{ publish_date } ) );
    }

    say STDERR "kept " . scalar( @{ $dated_stories } ) . " / " . scalar( @{ $stories } ) . " after date restriction";

    return $dated_stories;
}

# get all stories belonging to the media source
sub _get_existing_stories
{
    my ( $self ) = @_;

    my $date_clause = '';
    if ( my $start_date = $self->{ start_date } )
    {
        my $q_start_date = $self->db->dbh->quote( MediaWords::Util::SQL::increment_day( $start_date, -7 ) );
        $date_clause = "and date_trunc( 'day', publish_date ) >= ${ q_start_date }::date";
    }

    my $stories = $self->db->query( <<SQL, $self->{ media_id } )->hashes;
select
        stories_id, media_id, publish_date, url, guid, title
    from
        stories
    where
        media_id = ? $date_clause
SQL

    say STDERR "found " . scalar( @{ $stories } ) . " existing stories" if ( $self->debug );

    return $stories;
}

# return a list of just the new stories that don't have a duplicate in the existing stories
sub _dedup_new_stories
{
    my ( $self, $new_stories ) = @_;

    my $existing_stories = $self->_get_existing_stories();

    my $all_stories = [ @{ $new_stories }, @{ $existing_stories } ];

    my $url_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_url( $self->db, $all_stories );
    my $title_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_title( $self->db, $all_stories );

    my $all_dup_stories = [ @{ $url_dup_stories }, @{ $title_dup_stories } ];

    my $new_stories_lookup = {};
    map { $new_stories_lookup->{ $_->{ url } } = $_ } @{ $new_stories };

    my $dup_new_stories_lookup = {};
    for my $dup_stories ( @{ $all_dup_stories } )
    {
        for my $ds ( @{ $dup_stories } )
        {
            if ( $new_stories_lookup->{ $ds->{ url } } )
            {
                delete( $new_stories_lookup->{ $ds->{ url } } );
                $dup_new_stories_lookup->{ $ds->{ url } } = $ds;
            }
        }

    }

    my $nondup_stories = [ values( %{ $new_stories_lookup } ) ];
    my $dup_stories    = [ values( %{ $dup_new_stories_lookup } ) ];

    say STDERR "_dedup_new_stories: " . scalar( @{ $nondup_stories } ) . " new / " . scalar( @{ $dup_stories } ) . " dup";

    return ( $nondup_stories, $dup_stories );
}

# get a dummy feed just to hold the scraped stories because we have to give a feed to each new download
sub _get_scrape_feed
{
    my ( $self ) = @_;

    return $self->scrape_feed if ( $self->scrape_feed );

    my $db = $self->db;

    my $medium = $db->find_by_id( 'media', $self->media_id );

    my $feed_name = 'Scrape Feed';

    my $feed = $db->query( <<SQL, $medium->{ media_id }, $medium->{ url }, encode( 'utf8', $feed_name ) )->hash;
select * from feeds where media_id = ? and url = ? order by ( name = ? )
SQL

    $feed ||= $db->query( <<SQL, $medium->{ media_id }, $medium->{ url }, encode( 'utf8', $feed_name ) )->hash;
insert into feeds ( media_id, url, name, feed_status ) values ( ?, ?, ?, 'inactive' ) returning *
SQL

    $self->scrape_feed( $feed );

    return $feed;
}

# add story to a special 'scrape' feed
sub _add_story_to_scrape_feed
{
    my ( $self, $story ) = @_;

    $self->db->query( <<SQL, $self->_get_scrape_feed->{ feeds_id }, $story->{ stories_id } );
insert into feeds_stories_map ( feeds_id, stories_id ) values ( ?, ? )
SQL

}

# download the content for the story's url
sub _get_story_content
{
    my ( $self, $url ) = @_;

    say STDERR "fetching story url $url";

    my $ua = MediaWords::Util::Web::UserAgentDetermined;

    my $res = $ua->get( $url );

    if ( $res->is_success )
    {
        return $res->decoded_content;
    }
    else
    {
        warn( "Unable to fetch content for story '$url'" );
        return '';
    }

}

# add and extract download for story
sub _add_story_download
{
    my ( $self, $story, $content ) = @_;

    my $db = $self->db;

    if ( $content )
    {
        my $download = {
            feeds_id   => $self->_get_scrape_feed->{ feeds_id },
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

        MediaWords::DBI::Downloads::store_content( $db, $download, \$content );

        eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "ss" ); };

        warn "extract error processing download $download->{ downloads_id }: $@" if ( $@ );
    }
    else
    {
        my $download = {
            feeds_id   => $self->_get_scrape_feed->{ feeds_id },
            stories_id => $story->{ stories_id },
            url        => $story->{ url },
            host       => lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] ),
            type       => 'content',
            sequence   => 1,
            state      => 'pending',
            priority   => 1,
            extracted  => 'f'
        };

        $download = $db->create( 'downloads', $download );
    }
}

my $_scraped_tag;

sub _add_scraped_tag_to_story
{
    my ( $self, $story ) = @_;

    $_scraped_tag ||= MediaWords::Util::Tags::lookup_or_create_tag( $self->db, 'scraped:scraped' );

    $self->db->query( <<SQL, $_scraped_tag->{ tags_id }, $story->{ stories_id } );
insert into stories_tags_map ( tags_id, stories_id ) values ( ?, ? )
SQL

}

# add the stories to the database, including downloads
sub _add_new_stories
{
    my ( $self, $stories ) = @_;

    say STDERR "adding new stories to db ..." if ( $self->debug );

    my $total_stories = scalar( @{ $stories } );
    my $i             = 1;

    my $added_stories = [];
    for my $story ( @{ $stories } )
    {
        $self->db->begin;
        say STDERR "story: " . $i++ . " / $total_stories";

        my $content = $story->{ content };

        delete( $story->{ content } );
        delete( $story->{ normalized_url } );

        eval { $story = $self->db->create( 'stories', $story ) };
        if ( $@ )
        {
            carp( $@ . " - " . Dumper( $story ) );
            $self->db->rollback;
            next;
        }

        $self->_add_scraped_tag_to_story( $story );

        $self->_add_story_to_scrape_feed( $story );

        $self->_add_story_download( $story, $content );

        push( @{ $added_stories }, $story );
        $self->db->commit;
    }
}

# print stories
sub _print_stories
{
    my ( $self, $stories ) = @_;

    for my $s ( sort { $a->{ publish_date } cmp $b->{ publish_date } } @{ $stories } )
    {
        print STDERR <<END;
$s->{ publish_date } - $s->{ title } [$s->{ url }]
END
    }

}

# print list of deduped stories and dup stories
sub _print_story_diffs
{
    my ( $self, $deduped_stories, $dup_stories ) = @_;

    return unless ( $self->debug );

    say STDERR "dup stories:";
    $self->_print_stories( $dup_stories );

    say STDERR "deduped stories:";
    $self->_print_stories( $deduped_stories );

}

# call ImportStories::SUB->get_new_stories and add any stories within the
# specified date range to the given media source if there are not already duplicates in the media source
sub scrape_stories
{
    my ( $self ) = @_;

    my $new_stories = $self->get_new_stories();

    my $dated_stories = $self->_get_stories_in_date_range( $new_stories );

    my ( $deduped_new_stories, $dup_new_stories ) = $self->_dedup_new_stories( $new_stories );

    $self->_print_story_diffs( $deduped_new_stories, $dup_new_stories ) if ( $self->debug );

    my $added_stories = $self->_add_new_stories( $deduped_new_stories ) unless ( $self->dry_run );

    return $added_stories;
}

1;
