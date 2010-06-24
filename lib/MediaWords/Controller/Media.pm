package MediaWords::Controller::Media;

use Encode;
use strict;
use warnings;
use base 'Catalyst::Controller';

use Regexp::Common qw /URI/;
use YAML::Syck;
use Text::Trim;
use URI::Split;
use List::MoreUtils qw(any all none notall true false firstidx first_index
  lastidx last_index insert_after insert_after_string
  apply after after_incl before before_incl indexes
  firstval first_value lastval last_value each_array
  each_arrayref pairwise natatime mesh zip uniq minmax);

use Data::Dumper;
use MediaWords::Util::Tags;
use MediaWords::Util::Web;
use MediaWords::Util::HTML;
use Perl6::Say;

use constant ROWS_PER_PAGE => 25;

sub make_edit_form
{
    my ( $self, $c, $action ) = @_;

    my $form = HTML::FormFu->new(
        {
            load_config_file => $c->path_to() . '/root/forms/media.yml',
            method           => 'post',
            action           => $action
        }
    );

    #print STDERR Dumper($c->request);

    $form->stash->{ c } = $c;

    $form->process( $c->request );

    return $form;
}

sub create : Local
{
    my ( $self, $c ) = @_;

    $c->stash->{ template } = 'media/create.tt2';
}

sub create_batch : Local
{
    my ( $self, $c ) = @_;

    $c->stash->{ template } = 'media/create_batch.tt2';
}

# find the media source by the url or the url with/without the trailing slash
sub find_medium_by_url
{
    my ( $self, $c, $url ) = @_;

    my $base_url = $url;

    $base_url =~ m~^([a-z]*)://~;
    my $protocol = $1 || 'http';

    $base_url =~ s~^([a-z]+://)?(www\.)?~~;
    $base_url =~ s~/$~~;

    my $url_permutations =
      [ "$protocol://$base_url", "$protocol://www.$base_url", "$protocol://$base_url/", "$protocol://www.$base_url/" ];

    my $medium =
      $c->dbis->query( "select * from media where url in (?, ?, ?, ?) order by length(url) desc", @{ $url_permutations } )
      ->hash;

    return $medium;
}

# find the media source by the reseponse.  recurse back along the response to all of the chained redirects
# to see if we can find the media source by any of those urls.
sub find_medium_by_response
{
    my ( $self, $c, $response ) = @_;

    my $r = $response;

    my $medium;
    while ( $r && !( $medium = $self->find_medium_by_url( $c, $r->request->url ) ) )
    {
        $r = $r->previous;
    }

    return $medium;
}

# given a newline separated list of media urls, return a list of hashes in the form of
# { medium => $medium_hash, url => $url, tags_string => $tags_string, message => $error_message }
# the $medium_hash is the existing media source with the given url, or undef if no existing media source is found.
# the tags_string is everything after a space on a line, to be used to add tags to the media source later.
sub find_media_from_urls
{
    my ( $self, $c, $urls_string ) = @_;

    my $url_media = [];

    my $urls = [ split( "\n", $urls_string ) ];

    for my $tagged_url ( @{ $urls } )
    {
        my $medium;

        my ( $url, $tags_string ) = ( $tagged_url =~ /^\r*\s*([^\s]*)(?:\s+(.*))?/ );

        if ( $url !~ m~^[a-z]+://~ )
        {
            $url = "http://$url";
        }

        $medium->{ url }         = $url;
        $medium->{ tags_string } = $tags_string;

        if ( $url !~ /$RE{URI}/ )
        {
            $medium->{ message } = "'$url' is not a valid url";
        }

        $medium->{ medium } = $self->find_medium_by_url( $c, $url );

        push( @{ $url_media }, $medium );
    }

    return $url_media;
}

# given a set of url media (as returned by find_media_from_urls) and a url
# return the index of the media source in the list whose url is the same as the url fetched the response.
# note that the url should be the original url and not any redirected urls (such as might be stored in
# response->request->url).
sub get_url_medium_index_from_url
{
    my ( $self, $url_media, $url ) = @_;

    for ( my $i = 0 ; $i < @{ $url_media } ; $i++ )
    {

        #print STDERR "'$url_media->[ $i ]->{ url }' eq '$url'\n";
        if ( $url_media->[ $i ]->{ url } eq $url )
        {
            return $i;
        }
    }

    warn( "Unable to find url '" . $url . "' in url_media list" );
    return undef;
}

# given an lwp response, grab the title of the media source as the <title> content or missing that the response url
sub get_medium_title_from_response
{
    my ( $self, $response ) = @_;

    my $content = $response->decoded_content;

    my ( $title ) = ( $content =~ /<title>(.*?)<\/title>/is );
    $title = html_strip( $title );
    $title = trim( $title );
    $title ||= trim( $response->request->url );
    $title =~ s/\s+/ /g;

    $title =~ s/^\W*home\W*//i;

    $title = substr( $title, 0, 128 );

    return $title;
}

# fetch the url of all missing media and add those media with the titles from the fetched urls
sub add_missing_media_from_urls
{
    my ( $self, $c, $url_media ) = @_;

    my $fetch_urls = [ map { $_->{ url } } grep { !( $_->{ medium } ) } @{ $url_media } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $fetch_urls );

    for my $response ( @{ $responses } )
    {
        my $original_request = MediaWords::Util::Web->get_original_request( $response );
        my $url              = $original_request->url;

        my $url_media_index = $self->get_url_medium_index_from_url( $url_media, $url );
        if ( !defined( $url_media_index ) )
        {

            # add message to missing url_media in the loop at the end of this function
            next;
        }

        if ( !$response->is_success )
        {
            $url_media->[ $url_media_index ]->{ message } = "Unable to fetch medium url '$url': " . $response->status_line;
            next;
        }

        my $title = $self->get_medium_title_from_response( $response );

        my $medium = $self->find_medium_by_response( $c, $response );

        if ( !$medium )
        {
            if ( $medium = $c->dbis->query( "select * from media where name = ?", $title )->hash )
            {
                $url_media->[ $url_media_index ]->{ message } =
                  "using existing medium with duplicate title '$title' already in database for '$url'";
            }
            else
            {
                $medium = $c->dbis->create( 'media', { name => $title, url => $url, moderated => 'f', feeds_added => 'f' } );
            }
        }

        $url_media->[ $url_media_index ]->{ medium } = $medium;
    }

    # add error message for any url_media that were not found
    # if there's just one missing
    for my $url_medium ( @{ $url_media } )
    {
        if ( !$url_medium->{ medium } )
        {
            $url_medium->{ message } = "Unable to find medium for url '$url_medium->{ url }'";
        }
    }
}

# given a list of media sources as returned by find_media_from_urls, add the tags
# in the tags_string of each medium to that medium
sub add_media_tags_from_strings
{
    my ( $self, $c, $url_media, $global_tags_string ) = @_;

    for my $url_medium ( grep { $_->{ medium } } @{ $url_media } )
    {
        if ( $global_tags_string )
        {
            if ( $url_medium->{ tags_string } )
            {
                $url_medium->{ tags_string } .= ";$global_tags_string";
            }
            else
            {
                $url_medium->{ tags_string } = $global_tags_string;
            }
        }

        for my $tag_string ( split( /;/, $url_medium->{ tags_string } ) )
        {
            my ( $tag_set_name, $tag_name ) = split( ':', lc( $tag_string ) );

            my $tag_sets_id =
              $c->dbis->query( "select tag_sets_id from tag_sets where name = ?", lc( $tag_set_name ) )->list;
            if ( !$tag_sets_id )
            {
                $url_medium->{ message } .= " Unable to find tag set '$tag_set_name'";
                next;
            }

            my $tags_id = $c->dbis->find_or_create( 'tags', { tag => $tag_name, tag_sets_id => $tag_sets_id } )->{ tags_id };
            my $media_id = $url_medium->{ medium }->{ media_id };

            $c->dbis->find_or_create( 'media_tags_map', { tags_id => $tags_id, media_id => $media_id } );
        }
    }
}

# for each url in $urls, either find the medium associated with that
# url or the medium assocaited with the title from the given url or,
# if no medium is found, a newly created medium.  Return the list of
# all found or created media along with a list of error messages for the process.
sub find_or_create_media_from_urls
{
    my ( $self, $c, $urls_string, $tags_string ) = @_;

    my $url_media = $self->find_media_from_urls( $c, $urls_string );

    $self->add_missing_media_from_urls( $c, $url_media );

    $self->add_media_tags_from_strings( $c, $url_media, $tags_string );

    return [ grep { $_ } map { $_->{ message } } @{ $url_media } ];
}

# create a set of media sources from a list of urls; add any included tags to new or existing media sources
sub create_do : Local
{
    my ( $self, $c ) = @_;

    my $error_messages =
      $self->find_or_create_media_from_urls( $c, $c->request->param( 'urls' ), $c->request->param( 'tags' ) );

    my $status_msg;
    if ( @{ $error_messages } )
    {
        $status_msg = join( "\n",
            "Errors adding some media sources, see below.  Any urls not mentioned below were added successfully.",
            @{ $error_messages } );
    }
    else
    {
        $status_msg = "All media sources were added successfully.";
    }

    $c->response->redirect( $c->uri_for( '/media/list', { status_msg => $status_msg } ) );
}

sub edit : Local
{
    my ( $self, $c, $id ) = @_;

    $id += 0;

    my $form = $self->make_edit_form( $c, $c->uri_for( "/media/edit_do/$id" ) );

    my $medium = $c->dbis->find_by_id( 'media', $id );

    $form->default_values( $medium );

    $form->process;

    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'media/edit.tt2';
    $c->stash->{ title }    = 'Edit Media Source';
}

sub edit_do : Local
{
    my ( $self, $c, $id ) = @_;

    my $form = $self->make_edit_form( $c, $c->uri_for( "/media/edit_do/$id" ) );
    my $medium = $c->dbis->find_by_id( 'media', $id );

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'media/edit.tt2';
        $c->stash->{ title }    = 'Edit Media Source';
    }
    else
    {
        $c->dbis->update_by_id( 'media', $id, $form->params );

        if ( $medium->{ moderated } )
        {
            $c->response->redirect(
                $c->uri_for( '/feeds/list/' . $medium->{ media_id }, { status_msg => 'Media source updated.' } ) );
        }
        else
        {
            $c->response->redirect(
                $c->uri_for( '/media/moderate/' . ( $medium->{ media_id } - 1 ), { status_msg => 'Media source updated.' } )
            );
        }
    }
}

# after confirmation, mark the media source for deletion
sub delete : Local
{
    my ( $self, $c, $id, $confirm ) = @_;

    my $medium = $c->dbis->find_by_id( 'media', $id );

    my $status_msg;

    my $deleteme_tags_id = MediaWords::Util::Tags::lookup_or_create_tag( $c->dbis, 'workflow:deleteme' )->{ tags_id };

    my ( $marked_for_deletion ) =
      $c->dbis->query( "select 1 from media_tags_map " . "where tags_id = $deleteme_tags_id and media_id = ?", $id )->flat;

    if ( $marked_for_deletion )
    {
        $status_msg = 'Medium already marked for deletion.';
        $c->response->redirect( $c->uri_for( "/media/list", { status_msg => $status_msg } ) );
    }
    elsif ( !defined( $confirm ) )
    {
        $c->stash->{ medium }   = $medium;
        $c->stash->{ template } = 'media/delete.tt2';
    }
    else
    {
        if ( $confirm ne 'yes' )
        {
            $status_msg = 'Media source NOT marked for deletion.';
        }
        else
        {
            $c->dbis->query( "insert into media_tags_map (tags_id, media_id) values (?, ?)", $deleteme_tags_id, $id );
            $c->dbis->query( "update media set moderated = true where media_id = ?", $medium->{ media_id } );

            $status_msg = 'Media source marked for deletion.';
        }

        #print STDERR "moderated: $medium->{ moderated }\n";

        if ( $medium->{ moderated } )
        {
            $c->response->redirect( $c->uri_for( '/media/list', { status_msg => $status_msg } ) );
        }
        else
        {
            $c->response->redirect(
                $c->uri_for( '/media/moderate/' . ( $medium->{ media_id } - 1 ), { status_msg => $status_msg } ) );
        }
    }
}

# search for media matching search for the given keyword
# return the matching media from the given page along with a
# Data::Page object for the results
sub search_paged_media
{
    my ( $self, $c, $q, $page, $rows_per_page ) = @_;

    $q =~ s/^\s+//g;
    $q =~ s/\s+$//g;
    $q =~ s/[^\w]/_/g;

    $q = "'%$q%'";

    return $c->dbis->query_paged_hashes(
"select distinct m.media_id as media_id, m.name as name, m.url as url from media m left join ( media_tags_map mtm join (tags t join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id) ) on ( mtm.tags_id = t.tags_id) ) on (m.media_id = mtm.media_id) where (m.name like $q or m.url like $q or lower(ts.name||':'||t.tag) like $q) order by m.name",
        $page, $rows_per_page
    );
}

# return any media that might be a candidate for merging with the given media source
sub get_potential_merge_media
{
    my ( $self, $c, $medium ) = @_;

    my $host = lc( ( URI::Split::uri_split( $medium->{ url } ) )[ 1 ] );

    my @name_parts = split( /\./, $host );

    my $second_level_domain = $name_parts[ $#name_parts - 1 ];
    if ( ( $second_level_domain eq 'com' ) || ( $second_level_domain eq 'co' ) )
    {
        $second_level_domain = $name_parts[ $#name_parts - 2 ] || 'domainnotfound';
    }

    my $pattern = "%$second_level_domain%";

    return $c->dbis->query( "select * from media where ( name like ? or url like ? ) and media_id <> ?",
        $pattern, $pattern, $medium->{ media_id } )->hashes;
}

# go to the next media source in the moderation queue
sub moderate : Local
{
    my ( $self, $c, $prev_media_id ) = @_;

    $prev_media_id ||= 0;
    if ( $prev_media_id && $c->request->param( 'approve' ) )
    {
        $c->dbis->query( "update media set moderated = 't' where media_id = ?", $prev_media_id );
    }

    my $media = $c->dbis->query( "select * from media where moderated = 'f' and media_id > ? " . "  order by media_id",
        $prev_media_id )->hashes;

    my ( $medium, $tag_names, $feeds, $merge_media );

    if ( @{ $media } )
    {
        $medium    = $media->[ 0 ];
        $tag_names = $c->dbis->query(
            "select ts.name||':'||t.tag from tags t, media_tags_map mtm, tag_sets ts " .
              "  where t.tags_id = mtm.tags_id and t.tag_sets_id = ts.tag_sets_id and mtm.media_id = ?",
            $medium->{ media_id }
        )->flat;
        $feeds = $c->dbis->query( "select * from feeds where media_id = ? order by name", $medium->{ media_id } )->hashes;

        $merge_media = $self->get_potential_merge_media( $c, $medium );

        $#{ $merge_media } = List::Util::min( $#{ $merge_media }, 2 );
    }

    $c->stash->{ medium }      = $medium;
    $c->stash->{ tag_names }   = $tag_names;
    $c->stash->{ feeds }       = $feeds;
    $c->stash->{ queue_size }  = scalar( @{ $media } );
    $c->stash->{ merge_media } = $merge_media;
    $c->stash->{ template }    = 'media/moderate.tt2';
}

# display search form, and results of a query was submitted.
sub search : Local
{
    my ( $self, $c ) = @_;

    my $form = HTML::FormFu->new(
        {
            load_config_file => $c->path_to() . '/root/forms/media_search.yml',
            method           => 'get',
            action           => ''
        }
    );

    $form->process( $c->request );

    my $p = $c->request->param( 'p' ) || 1;
    my $q = $c->request->param( 'q' );
    my $f = $c->request->param( 'f' );
    my @m = $c->request->param( 'm' );

    my ( $media, $pager );

    if ( $q )
    {
        ( $media, $pager ) = $self->search_paged_media( $c, $q, $p, ROWS_PER_PAGE );
    }
    elsif ( $f )
    {
        ( $media, $pager ) = $c->dbis->query_paged_hashes(
            "select * from media m " . "where not exists (select 1 from feeds f where f.media_id = m.media_id) " .
              "order by media_id desc",
            $p, ROWS_PER_PAGE
        );
    }
    elsif ( @m )
    {
        $media = $c->dbis->query( "select * from media where media_id in (??) order by name", @m )->hashes;
    }
    else
    {
        ( $media, $pager ) = $c->dbis->query_paged_hashes( "select * from media order by name", $p, ROWS_PER_PAGE );
    }

    for my $m ( @{ $media } )
    {
        $m->{ tag_names } = $c->dbis->query(
            "select ts.name||':'||t.tag from tags t, media_tags_map mtm, tag_sets ts " .
              "where t.tags_id = mtm.tags_id and t.tag_sets_id = ts.tag_sets_id and mtm.media_id = ?",
            $m->{ media_id }
        )->flat;
        ( $m->{ feed_count } ) = $c->dbis->query( "select count(*) from feeds where media_id = ?", $m->{ media_id } )->flat;
    }

    $c->stash->{ media }     = $media;
    $c->stash->{ pager }     = $pager;
    $c->stash->{ pager_url } = $c->uri_for( '/media/search', { q => $q, m => \@m, f => $f } );

    $c->stash->{ q }        = $q;
    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'media/search.tt2';
}

# alias for search
sub list : Local
{
    my $self = shift( @_ );
    return $self->search( @_ );
}

sub edit_tags : Local
{
    my ( $self, $c, $media_id ) = @_;

    if ( !$media_id )
    {
        die( "no media_id" );
    }

    my $medium = $c->dbis->find_by_id( 'media', $media_id );
    if ( !$medium )
    {
        die( "Unable to find medium $media_id" );
    }

    my $action = $c->uri_for( '/media/edit_tags_do/' . $media_id );

    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $media_id, 'media' );

    $c->stash->{ form }     = $form;
    $c->stash->{ medium }   = $medium;
    $c->stash->{ template } = 'media/edit_tags.tt2';
}

sub edit_tags_do : Local
{
    my ( $self, $c, $media_id ) = @_;

    if ( !$media_id )
    {
        die( "no media_id" );
    }

    my $medium = $c->dbis->find_by_id( 'media', $media_id );
    if ( !$medium )
    {
        die( "Unable to find medium $media_id" );
    }

    my $action = $c->uri_for( '/media/edit_tags_do/' ) . $media_id;
    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $media_id, 'media' );

    if ( !$form->submitted_and_valid )
    {
        return $self->edit_tags( $c, $media_id );
    }

    MediaWords::Util::Tags->save_tags( $c, $media_id, 'media' );

    $c->response->redirect( $c->uri_for( "/feeds/list/" . $media_id, { status_msg => 'Tags updated.' } ) );
}

# delete all feeds belonging to this media source
sub delete_feeds : Local
{
    my ( $self, $c, $media_id, $confirm ) = @_;

    my $medium = $c->dbis->query( "select * from media where media_id = ?", $media_id )->hash;

    if ( $medium->{ moderated } )
    {
        my $error = "You can only delete the feeds of media sources that have not yet been moderated";
        $c->response->redirect(
            $c->uri_for( "/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $error } ) );
        return;
    }

    if ( !defined( $confirm ) )
    {
        $c->stash->{ medium }   = $medium;
        $c->stash->{ template } = 'media/delete_feeds.tt2';
    }
    else
    {
        my $status_msg;
        if ( $confirm ne 'yes' )
        {
            $status_msg = 'Media source feed deletion cancelled.';
        }
        else
        {
            $c->dbis->query( "delete from feeds where media_id = ?", $media_id );
            $status_msg = 'Media source feeds deleted.';
        }

        $c->response->redirect(
            $c->uri_for( "/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $status_msg } ) );
    }
}

# delete the feed without confirmation, but only if it is from an unmoderated media source
sub delete_unmoderated_feed : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    my $medium =
      $c->dbis->query( "select m.* from media m, feeds f where f.feeds_id = ? and f.media_id = m.media_id", $feeds_id )
      ->hash;

    if ( $medium->{ moderated } )
    {
        my $error = "You can only delete the feeds of media sources that have not yet been moderated";
        $c->response->redirect(
            $c->uri_for( "/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $error } ) );
        return;
    }

    $c->dbis->query( "delete from feeds where feeds_id = ?", $feeds_id );
    my $status_msg = 'Media source feed deleted.';
    $c->response->redirect(
        $c->uri_for( "/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $status_msg } ) );
}

# merge the tags of medium_a into medium_b
sub merge_media_tags
{
    my ( $self, $c, $medium_a, $medium_b ) = @_;

    my $tags_ids =
      $c->dbis->query( "select tags_id from media_tags_map mtm where media_id = ?", $medium_a->{ media_id } )->flat;

    for my $tags_id ( @{ $tags_ids } )
    {
        $c->dbis->find_or_create( 'media_tags_map', { media_id => $medium_b->{ media_id }, tags_id => $tags_id } );
    }
}

# merge one media source the tags of medium_a into medium_b and delete medium_b
sub merge : Local
{
    my ( $self, $c, $media_id_a, $media_id_b, $confirm ) = @_;

    my $medium_a = $c->dbis->find_by_id( 'media', $media_id_a );
    my $medium_b = $c->dbis->find_by_id( 'media', $media_id_b );

    $confirm ||= 'no';

    if ( !$medium_a->{ moderated } && ( $confirm eq 'yes' ) )
    {
        $self->merge_media_tags( $c, $medium_a, $medium_b );

        $c->dbis->delete_by_id( 'media', $medium_a->{ media_id } );

        $c->response->redirect( $c->uri_for( '/media/moderate/' . $medium_a->{ media_id } ) );
    }
    else
    {
        my $status_msg;
        if ( $medium_a->{ moderated } )
        {
            $status_msg = "$medium_a->{ name } must not have been moderated to be merged.";
        }

        $c->stash->{ medium_a }   = $medium_a;
        $c->stash->{ medium_b }   = $medium_b;
        $c->stash->{ status_msg } = $status_msg;
        $c->stash->{ template }   = 'media/merge.tt2';
    }
}

sub _rate_full_text_rss_likely_hood
{
    ( my $medium ) = @_;

    my $ret =
      ( $medium->{ avg_similarity } || 0 ) * 10 - 5 *
      (
        abs( $medium->{ avg_extracted_length } - $medium->{ avg_rss_length } ) /
          ( $medium->{ avg_extracted_length } != 0.0 ? $medium->{ avg_extracted_length } : 0.01 ) );

    #say STDERR "_rate_full_text_rss_likely_hood returning '$ret'";

    if ( $ret eq 'nan' )
    {
        say STDERR 5 *
          ( abs( $medium->{ avg_extracted_length } - $medium->{ avg_rss_length } ) / $medium->{ avg_extracted_length } );
        say STDERR ( $medium->{ avg_similarity } || 0 );
        print STDERR Dumper( $medium );
        print Dumper( $medium );
        die "Error calculating full_text_rss_likely_hood for media id " . $medium->{ media_id };
    }
    return $ret;
}

# display search form, and results of a query was submitted.
sub do_find_likely_full_text_rss : Local
{
    my ( $self, $c ) = @_;

    my $media_ids = $c->request->parameters->{ full_text_rss };

    $c->dbis->query( "UPDATE media set full_text_rss = true where media_id in (??) ", @$media_ids );

    my $status_msg = 'UPDATED media_ids: ' . ( join ',', @{ $media_ids } );

    #say STDERR $status_msg;

    $c->response->redirect( $c->uri_for( '/media/find_likely_full_text_rss/', { status_msg => $status_msg } ) );
}

sub _get_likely_rss_full_text_media_list
{
    my ( $self, $c ) = @_;

    my $media =
      $c->dbis->query( "select * from media_rss_full_text_detection_data natural join media where full_text_rss is null" )
      ->hashes;

    $media = [ grep { $_->{ avg_similarity } ne 'NaN' } @{ $media } ];

    $media = [ sort { _rate_full_text_rss_likely_hood( $a ) <=> _rate_full_text_rss_likely_hood( $b ) } @{ $media } ];

    $media = [ reverse @{ $media } ];

    return $media;
}

# display search form, and results of a query was submitted.
sub find_likely_full_text_rss : Local
{
    my ( $self, $c ) = @_;

    my $form = HTML::FormFu->new(
        {
            load_config_file => $c->path_to() . '/root/forms/media_search.yml',
            method           => 'get',
            action           => ''
        }
    );

    $form->process( $c->request );

    my $p = $c->request->param( 'p' ) || 1;
    my $q = $c->request->param( 'q' );
    my $f = $c->request->param( 'f' );
    my @m = $c->request->param( 'm' );

    my $media = $self->_get_likely_rss_full_text_media_list( $c );

    for my $m ( @{ $media } )
    {
        ( $m->{ feed_count } ) = $c->dbis->query( "select count(*) from feeds where media_id = ?", $m->{ media_id } )->flat;
    }

    $c->stash->{ media } = $media;

    $c->stash->{ pager_url } = $c->uri_for( '/media/search', { q => $q, m => \@m, f => $f } );

    $c->stash->{ q } = $q;

    $c->stash->{ template } = 'media/find_likely_full_text.tt2';
}

sub eval_rss_full_text : Local
{
    my ( $self, $c, $id ) = @_;

    $id += 0;

    my ( $medium ) =
      $c->dbis->query( " select * from media_rss_full_text_detection_data natural join media where media_id = ? ", $id )
      ->hashes->[ 0 ];

    #say STDERR Dumper( $medium );

    my $action = $c->uri_for( '/media/do_eval_rss_full_text/' ) . $id;

    my $recent_stories = $c->dbis->query(
        "select stories.* from stories natural join downloads natural join download_texts " .
          " where media_id = ? order by publish_date desc limit 3",
        $id
    )->hashes;

    foreach my $story ( @{ $recent_stories } )
    {
        $story->{ extracted_text } = MediaWords::DBI::Stories::get_extracted_text( $c->dbis, $story );
    }

    #Find the source after this one when media are ranked as being likely to have full text rss.
    my $media = $self->_get_likely_rss_full_text_media_list( $c );

    my $medium_index = first_index { $_->{ media_id } == $id } @{ $media };

    my $next_index;

    if ( ( $medium_index < ( scalar( @{ $media } ) - 1 ) ) && ( $medium_index > -1 ) )
    {
        $next_index = $medium_index + 1;
    }
    else
    {
        $next_index = 0;
    }

    my $next_media_id = $media->[ $next_index ]->{ media_id };

    # say STDERR Dumper( $recent_stories );

    $c->stash->{ next_media_id } = $next_media_id;

    $c->stash->{ stories } = $recent_stories;

    $c->stash->{ medium } = $medium;

    $c->stash->{ template } = 'media/eval_rss_full_text.tt2';
    $c->stash->{ title }    = 'Eval Media RSS FULL TEXT';

}

sub do_eval_rss_full_text : Local
{
    my ( $self, $c, $id ) = @_;

    my $full_text_state = $c->request->parameters->{ full_text_rss };

    die "New RSS full text value undefined " if !defined( $full_text_state );

    #say STDERR Dumper( $full_text_state );

    if ( $full_text_state ne '' )
    {
        $c->dbis->query( "UPDATE media set full_text_rss = ? where media_id = ?", $full_text_state, $id );
    }
    else
    {
        $c->dbis->query( "UPDATE media set full_text_rss = NULL where media_id = ?", $id );
    }

    my $status_msg = "UPDATED media: $id";

    say STDERR $status_msg;

    $c->response->redirect( $c->uri_for( '/media/eval_rss_full_text/' . $id, { status_msg => $status_msg } ) );
}

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

GPL

=cut

1;
