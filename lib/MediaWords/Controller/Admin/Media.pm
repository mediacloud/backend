package MediaWords::Controller::Admin::Media;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Encode;
use strict;
use warnings;
use base 'Catalyst::Controller';

use Regexp::Common qw /URI/;

#use YAML::Syck;
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
use MediaWords::DBI::Feeds;
use MediaWords::DBI::Media;
use JSON;
use URI;

use if $] < 5.014, Switch => 'Perl6';
use if $] >= 5.014, feature => 'switch';

use constant ROWS_PER_PAGE => 25;

sub _make_edit_form
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

sub create_batch : Local
{
    my ( $self, $c ) = @_;

    $c->stash->{ template } = 'media/create_batch.tt2';
}

sub media_tags_search_json : Local
{
    my ( $self, $c ) = @_;

    my $term = $c->req->param( 'term' ) || 0;

    say STDERR "$term";

    $term = $term . '%';

    my ( $tag_set_part, $tag_part ) = split ':', $term;

    my $terms = [];

    if ( $tag_part eq '' )
    {
        $tag_part = $tag_set_part;
        $terms    = $c->dbis->query(
"select name ||':' || tag from tag_sets natural join tags where tags_id in ( select distinct(tags_id) from media_tags_map ) "
              . " and (name like ? or tag like ? ) order by name, tag;",
            $tag_set_part, $tag_part
        )->flat;
    }
    else
    {
        $terms = $c->dbis->query(
"select name ||':' || tag from tag_sets natural join tags where tags_id in ( select distinct(tags_id) from media_tags_map ) "
              . " and (name = ? and tag like ? ) order by name, tag;",
            $tag_set_part, $tag_part
        )->flat;
    }

    #say STDERR Dumper( $terms );
    #say STDERR encode_json($terms);

    $c->res->body( encode_json( $terms ) );

    return;
}

# create a set of media sources from a list of urls; add any included tags to new or existing media sources
sub create_do : Local
{
    my ( $self, $c ) = @_;

    my $error_messages = MediaWords::DBI::Media::find_or_create_media_from_urls(
        $c->dbis,
        $c->request->param( 'urls' ),
        $c->request->param( 'tags' )
    );

    my $status_msg;
    if ( @{ $error_messages } )
    {
        $status_msg = join( "\n",
            "Errors adding some media sources, see below.  Any urls not mentioned below were added successfully.",
            @{ $error_messages } );

        if ( length( $status_msg ) > 2048 )
        {
            $status_msg = substr( $status_msg, 0, 2000 ) . "...\nAdditional errors not listed.";
        }
    }
    else
    {
        $status_msg = "All media sources were added successfully.";
    }

    $c->response->redirect( $c->uri_for( '/admin/media/list', { status_msg => $status_msg } ) );
}

sub edit : Local
{
    my ( $self, $c, $id ) = @_;

    $id += 0;

    my $form = $self->_make_edit_form( $c, $c->uri_for( "/admin/media/edit_do/$id" ) );

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

    my $form = $self->_make_edit_form( $c, $c->uri_for( "/admin/media/edit_do/$id" ) );
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
                $c->uri_for( '/admin/feeds/list/' . $medium->{ media_id }, { status_msg => 'Media source updated.' } ) );
        }
        else
        {
            $c->response->redirect(
                $c->uri_for(
                    '/admin/media/moderate/' . ( $medium->{ media_id } - 1 ),
                    { status_msg => 'Media source updated.' }
                )
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
        $c->response->redirect( $c->uri_for( "/admin/media/list", { status_msg => $status_msg } ) );
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
            $c->response->redirect( $c->uri_for( '/admin/media/list', { status_msg => $status_msg } ) );
        }
        else
        {
            $c->response->redirect(
                $c->uri_for( '/admin/media/moderate/' . ( $medium->{ media_id } - 1 ), { status_msg => $status_msg } ) );
        }
    }
}

# search for media matching search for the given keyword
# return the matching media from the given page along with a
# Data::Page object for the results
sub _search_paged_media
{
    my ( $self, $c, $q, $page, $rows_per_page ) = @_;

    $q =~ s/^\s+//g;
    $q =~ s/\s+$//g;
    $q =~ s/[^\w]/_/g;

    $q = "'%$q%'";

    return $c->dbis->query_paged_hashes(
"select distinct m.media_id as media_id, m.name as name, m.url as url from media m left join ( media_tags_map mtm join (tags t join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id) ) on ( mtm.tags_id = t.tags_id) ) on (m.media_id = mtm.media_id) where (m.name ilike $q or m.url ilike $q or lower(ts.name||':'||t.tag) ilike $q) order by m.name",
        [], $page, $rows_per_page
    );
}

# return any media that might be a candidate for merging with the given media source
sub _get_potential_merge_media
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
    my ( $self, $c, $prev_media_id, $media_sets_id ) = @_;

    $prev_media_id ||= 0;
    if ( $prev_media_id && $c->request->param( 'approve' ) )
    {
        $c->dbis->query( "update media set moderated = 't', feeds_added = 't' where media_id = ?", $prev_media_id );
    }

    my $media;

    my $media_set_clause = "1=1";
    if ( defined( $media_sets_id ) )
    {
        $media_sets_id += 0;
        $media_set_clause = "media_id in ( select media_id from media_sets_media_map where media_sets_id = $media_sets_id )";
    }

    $media = $c->dbis->query(
"select * from media where moderated = 'f' and feeds_added = 't' and media_id > ? and $media_set_clause order by media_id",
        $prev_media_id
    )->hashes;

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

        $merge_media = $self->_get_potential_merge_media( $c, $medium );

        $#{ $merge_media } = List::Util::min( $#{ $merge_media }, 2 );
    }

    my ( $num_media_pending_feeds ) =
      $c->dbis->query( "select count(*) from media where feeds_added = 'f' and moderated = 'f'" )->flat;

    $c->stash->{ media_sets_id }           = $media_sets_id;
    $c->stash->{ medium }                  = $medium;
    $c->stash->{ tag_names }               = $tag_names;
    $c->stash->{ feeds }                   = $feeds;
    $c->stash->{ queue_size }              = scalar( @{ $media } );
    $c->stash->{ merge_media }             = $merge_media;
    $c->stash->{ num_media_pending_feeds } = $num_media_pending_feeds;
    $c->stash->{ template }                = 'media/moderate.tt2';
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
        ( $media, $pager ) = $self->_search_paged_media( $c, $q, $p, ROWS_PER_PAGE );
    }
    elsif ( $f )
    {
        ( $media, $pager ) = $c->dbis->query_paged_hashes(
            "select * from media m " . "where not exists (select 1 from feeds f where f.media_id = m.media_id) " .
              "order by media_id desc",
            [], $p, ROWS_PER_PAGE
        );
    }
    elsif ( @m )
    {
        $media = $c->dbis->query( "select * from media where media_id in (??) order by name", @m )->hashes;
    }
    else
    {
        ( $media, $pager ) = $c->dbis->query_paged_hashes( "select * from media order by name", [], $p, ROWS_PER_PAGE );
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
    $c->stash->{ pager_url } = $c->uri_for( '/admin/media/search', { q => $q, m => \@m, f => $f } );

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

    my $action = $c->uri_for( '/admin/media/edit_tags_do/' . $media_id );

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

    my $action = $c->uri_for( '/admin/media/edit_tags_do/' ) . $media_id;
    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $media_id, 'media' );

    if ( !$form->submitted_and_valid )
    {
        return $self->edit_tags( $c, $media_id );
    }

    MediaWords::Util::Tags->save_tags( $c, $media_id, 'media' );

    $c->response->redirect( $c->uri_for( "/admin/feeds/list/" . $media_id, { status_msg => 'Tags updated.' } ) );
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
            $c->uri_for( "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $error } ) );
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
            my $feeds = $c->dbis->query( "select * from feeds where media_id = ?", $media_id )->hashes;
            map { MediaWords::DBI::Feeds::delete_feed_and_stories( $c->dbis, $_->{ feeds_id } ) } @{ $feeds };
            $status_msg = 'Media source feeds deleted.';
        }

        $c->response->redirect(
            $c->uri_for( "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $status_msg } ) );
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
            $c->uri_for( "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $error } ) );
        return;
    }

    my $feed = $c->dbis->find_by_id( 'feeds', $feeds_id );

    MediaWords::DBI::Feeds::delete_feed_and_stories( $c->dbis, $feed->{ feeds_id } );
    my $status_msg = 'Media source feed deleted.';
    $c->response->redirect(
        $c->uri_for( "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $status_msg } ) );
}

# keep only the one feed for the medium
sub keep_single_feed : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    my $medium =
      $c->dbis->query( "select m.* from media m, feeds f where f.feeds_id = ? and f.media_id = m.media_id", $feeds_id )
      ->hash;

    if ( $medium->{ moderated } )
    {
        my $error = "You can only delete the feeds of media sources that have not yet been moderated";
        $c->response->redirect(
            $c->uri_for( "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $error } ) );
        return;
    }

    # make sure feeds_id is a num
    $feeds_id += 0;

    my $feeds = $c->dbis->query( <<END, $medium->{ media_id }, $feeds_id )->hashes;
select * from feeds where media_id = ? and feeds_id <> ?
END
    map { MediaWords::DBI::Feeds::delete_feed_and_stories( $c->dbis, $_->{ feeds_id } ) } @{ $feeds };

    my $status_msg = 'Media source feeds deleted.';

    if ( $c->req->param( 'approve' ) )
    {
        $c->response->redirect( $c->uri_for( "/admin/media/moderate/$medium->{ media_id }", { approve => 1 } ) );
    }
    else
    {
        $c->response->redirect(
            $c->uri_for( "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ), { status_msg => $status_msg } ) );
    }
}

# merge the tags of medium_a into medium_b
sub _merge_media_tags
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
        $self->_merge_media_tags( $c, $medium_a, $medium_b );

        $c->dbis->delete_by_id( 'media', $medium_a->{ media_id } );

        $c->response->redirect( $c->uri_for( '/admin/media/moderate/' . $medium_a->{ media_id } ) );
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

    my $post_params = $c->request->body_parameters();

    #say Dumper($post_params);

    my @media_full_text_params = grep { $_ =~ /media_\d+_full_text_rss/ } sort keys %{ $post_params };

    #say Dumper(@media_full_text_params);

    foreach my $medium_full_text_param ( @media_full_text_params )
    {
        $medium_full_text_param =~ /media_(\d+)_full_text_rss/;

        my $media_id = $1;
        die "Invalid $media_id " unless $media_id =~ /\d+/;

        my $full_text_value = $post_params->{ $medium_full_text_param };

        given ( $full_text_value )
        {
            when ( 1 ) { $c->dbis->query( "UPDATE media set full_text_rss = true where media_id = ?",  $media_id ); }
            when ( 0 ) { $c->dbis->query( "UPDATE media set full_text_rss = false where media_id = ?", $media_id ); }

            when ( '' ) { $c->dbis->query( "UPDATE media set full_text_rss = NULL where media_id = ?", $media_id ); }
            default { die "Bad case in switch :'$full_text_value'"; }

        }
    }

    #$c->dbis->query( "UPDATE media set full_text_rss = true where media_id in (??) ", @$media_ids );

    my $status_msg = "updated";

    #$status_msg = 'UPDATED media_ids: ' . ( join ',', @{ $media_ids } );

    #say STDERR $status_msg;

    $c->response->redirect( $c->uri_for( '/admin/media/find_likely_full_text_rss/', { status_msg => $status_msg } ) );
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

    foreach my $medium ( @{ $media } )
    {
        $medium->{ full_text_rss_rating } = _rate_full_text_rss_likely_hood( $medium );
    }

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

    $c->stash->{ pager_url } = $c->uri_for( '/admin/media/search', { q => $q, m => \@m, f => $f } );

    $c->stash->{ q } = $q;

    $c->stash->{ template } = 'media/find_likely_full_text.tt2';
}

sub _get_next_media_id
{
    my ( $self, $c, $id ) = @_;

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

    return $next_media_id;
}

sub eval_rss_full_text : Local
{
    my ( $self, $c, $id ) = @_;

    $id += 0;

    my ( $medium ) =
      $c->dbis->query( " select * from media_rss_full_text_detection_data natural join media where media_id = ? ", $id )
      ->hashes->[ 0 ];

    $medium->{ full_text_rss_rating } = _rate_full_text_rss_likely_hood( $medium );

    #say STDERR Dumper( $medium );

    my $action = $c->uri_for( '/admin/media/do_eval_rss_full_text/' ) . $id;

    my $recent_stories = $c->dbis->query(
        "select stories.* from stories natural join downloads natural join download_texts " .
          " where media_id = ? order by publish_date desc limit 3",
        $id
    )->hashes;

    foreach my $story ( @{ $recent_stories } )
    {
        $story->{ extracted_text } = MediaWords::DBI::Stories::get_extracted_text( $c->dbis, $story );
    }

    my $next_media_id = $self->_get_next_media_id( $c, $id );

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

    my $next_media_id = $self->_get_next_media_id( $c, $id );

    my $status_msg = "UPDATED media: $id - Here's the next source";

    #say STDERR $status_msg;

    $c->response->redirect(
        $c->uri_for( '/admin/media/eval_rss_full_text/' . $next_media_id, { status_msg => $status_msg } ) );
}

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

GPL

=cut

1;
