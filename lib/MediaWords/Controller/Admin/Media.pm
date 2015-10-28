package MediaWords::Controller::Admin::Media;
use Modern::Perl "2013";
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
use MediaWords::DBI::Stories;
use JSON;
use Readonly;
use URI;

use if $] < 5.014, Switch => 'Perl6';
use if $] >= 5.014, feature => 'switch';

Readonly my $ROWS_PER_PAGE => 25;

# if called with a controversies_id param, add the controversy specific media
# types to the form
sub _add_controversy_media_type_to_form
{
    my ( $c, $form ) = @_;

    my $controversies_id = $c->req->params->{ controversies_id };
    return unless ( $controversies_id );

    my $db = $c->dbis;

    my $media_types = $db->query( <<END, $controversies_id )->hashes;
select t.*
    from tags t
        join controversies c on ( c.media_type_tag_sets_id = t.tag_sets_id )
    where
        c.controversies_id = ?
    order by t.label = 'Not Typed' desc, t.tag
END

    return unless ( @{ $media_types } );

    my $controversy = $db->find_by_id( 'controversies', $controversies_id );

    my $media_type_options = [ map { [ $_->{ tags_id }, $_->{ label } ] } @{ $media_types } ];

    my $cmt_element = $form->element(
        {
            name    => 'controversy_media_type_tags_id',
            label   => "Controversy Specific Media Type",
            comment => 'type of media source, applies only to the specific ' . $controversy->{ name } . ' controversy',
            type    => 'Select',
            options => $media_type_options
        }
    );

    my $mt_element = $form->get_element( { name => 'media_type_tags_id' } );

    $form->insert_after( $cmt_element, $mt_element );
}

sub _make_edit_form
{
    my ( $self, $c, $action ) = @_;

    my $db = $c->dbis;

    my $form = HTML::FormFu->new(
        {
            load_config_file => $c->path_to() . '/root/forms/media.yml',
            method           => 'post',
            action           => $action
        }
    );

    $form->stash->{ c } = $c;

    my $media_types = MediaWords::DBI::Media::get_media_type_tags( $db );

    my $media_type_options = [ map { [ $_->{ tags_id }, $_->{ label } ] } @{ $media_types } ];

    $form->get_element( { name => 'media_type_tags_id' } )->options( $media_type_options );

    _add_controversy_media_type_to_form( $c, $form );

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

    my $db = $c->dbis;

    my $term = $c->req->param( 'term' ) || 0;

    say STDERR "$term";

    $term = $term . '%';

    my ( $tag_set_part, $tag_part ) = split ':', $term;

    my $terms = [];

    if ( !defined( $tag_part ) || $tag_part eq '' )
    {
        $tag_part = $tag_set_part;
        $terms    = $db->query(
"select name ||':' || tag from tag_sets natural join tags where tags_id in ( select distinct(tags_id) from media_tags_map ) "
              . " and (name like ? or tag like ? ) order by name, tag;",
            $tag_set_part, $tag_part
        )->flat;
    }
    else
    {
        $terms = $db->query(
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

    my $db = $c->dbis;

    my $error_messages = MediaWords::DBI::Media::find_or_create_media_from_urls(
        $db,
        $c->request->param( 'urls' ),
        $c->request->param( 'tags' )
    );

    my $status_msg;
    if ( @{ $error_messages } )
    {
        $status_msg = join( "\n", @{ $error_messages } );

        if ( length( $status_msg ) > 2048 )
        {
            $status_msg = substr( $status_msg, 0, 2000 ) . "...\nAdditional errors not listed.";
        }
    }
    else
    {
        $status_msg = "All media sources were added successfully.";
    }

    $status_msg .= "<br />The system is working on scraping feeds for feedless media.  That process may take a long time.";

    $c->response->redirect( $c->uri_for( '/admin/media/list', { status_msg => $status_msg } ) );
}

sub edit : Local
{
    my ( $self, $c, $id ) = @_;

    $self->edit_do( $c, $id );
}

# if the name or url already exists for another media source, set an error message and invalidate the form
sub _require_unique_name_and_url
{
    my ( $c, $form, $medium ) = @_;

    my $db = $c->dbis;
    my $p  = $form->params;

    my $dup_fields = [];
    for my $field ( qw(name url) )
    {
        my $dup = $db->query( <<END, $medium->{ media_id }, $p->{ $field } )->hash;
select * from media where media_id <> ? and $field = ?
END
        push( @{ $dup_fields }, $field ) if ( $dup );
    }

    if ( @{ $dup_fields } )
    {
        $c->stash->{ error_msg } = join( '.', map { "Another medium with the $_ '$p->{ $_ }'" } @{ $dup_fields } );
        $form->invalidate();
    }
}

# add controversy_media_type_tags_id field to the medium if $c->req->params->{ controversies_id } is
# specified and if there is a controversy media type for the medium / controversy
sub _add_controversy_media_type
{
    my ( $c, $medium ) = @_;

    my $controversies_id = $c->req->params->{ controversies_id };
    return unless ( $controversies_id );

    my $db = $c->dbis;

    my ( $tags_id ) = $db->query( <<END, $medium->{ media_id }, $controversies_id )->flat;
select t.tags_id
    from media_tags_map mtm
        join tags t on ( mtm.tags_id = t.tags_id )
        join controversies c on ( t.tag_sets_id = c.media_type_tag_sets_id )
    where
        mtm.media_id = ? and
        c.controversies_id = ?
END

    $medium->{ controversy_media_type_tags_id } = $tags_id;
}

# display edit form or save edit update
sub edit_do : Local
{
    my ( $self, $c, $id ) = @_;

    my $db = $c->dbis;

    $id += 0;

    my $form = $self->_make_edit_form( $c, $c->uri_for( "/admin/media/edit_do/$id" ) );
    my $medium = $db->query( "select * from media_with_media_types where media_id = ?", $id )->hash
      || die( "unknown medium: $id" );

    _add_controversy_media_type( $c, $medium );

    $form->default_values( $medium );

    $form->process( $c->req );

    # # Save the original referer to the edit form so we can get back to that URL later on
    my $el_referer = $form->get_element( { name => 'referer', type => 'Hidden' } );
    $el_referer->value( $c->req->referer ) unless ( $el_referer->value );

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'media/edit.tt2';
        $c->stash->{ title }    = 'Edit Media Source';
    }
    else
    {
        my $form_params = { %{ $form->params } };    # shallow copy to make editable

        # remove from copy so update_by_id doesn't try to update non-existent media field
        delete( $form_params->{ reason } );
        delete( $form_params->{ referer } );

        # Set the database-compatible boolean checkbox values (otherwise they're empty strings)
        $form_params->{ full_text_rss }     ||= 0;
        $form_params->{ foreign_rss_links } ||= 0;

        MediaWords::DBI::Media::update_media_type( $db, $medium, $c->req->params->{ media_type_tags_id } );
        MediaWords::DBI::Media::update_media_type( $db, $medium, $c->req->params->{ controversy_media_type_tags_id } );
        delete( $form_params->{ media_type_tags_id } );
        delete( $form_params->{ controversy_media_type_tags_id } );

        $db->update_by_id( 'media', $id, $form_params );

        # Make a logged update
        $db->update_by_id_and_log( 'media', $id, $medium, $form_params, 'media_edit', $form->params->{ reason },
            $c->user->username );

        my $msg = "Media source updated.";
        if ( $form->params->{ referer } )
        {
            my $uri = URI->new( $form->params->{ referer } );
            $uri->query_param_delete( 'status_msg' );
            $uri->query_param_append( 'status_msg' => $msg );
            $c->res->redirect( $uri->as_string );
        }
        elsif ( $medium->{ moderated } )
        {
            $c->res->redirect( $c->uri_for( '/admin/feeds/list/' . $medium->{ media_id }, { status_msg => $msg } ) );
        }
        else
        {
            my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;
            $c->res->redirect(
                $c->uri_for(
                    '/admin/media/moderate/' . ( $medium->{ media_id } - 1 ),
                    { status_msg => $msg, media_tags_id => $media_tags_id }
                )
            );
        }
    }
}

# after confirmation, mark the media source for deletion
sub delete : Local
{
    my ( $self, $c, $id, $confirm ) = @_;

    my $db = $c->dbis;

    my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;

    my $medium = $db->find_by_id( 'media', $id );

    my $status_msg;

    my $deleteme_tags_id = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'workflow:deleteme' )->{ tags_id };

    my ( $marked_for_deletion ) =
      $db->query( "select 1 from media_tags_map " . "where tags_id = $deleteme_tags_id and media_id = ?", $id )->flat;

    if ( $marked_for_deletion )
    {
        $status_msg = 'Medium already marked for deletion.';
        $c->response->redirect( $c->uri_for( "/admin/media/list", { status_msg => $status_msg } ) );
    }
    elsif ( !defined( $confirm ) )
    {
        $c->stash->{ medium }        = $medium;
        $c->stash->{ media_tags_id } = $media_tags_id;
        $c->stash->{ template }      = 'media/delete.tt2';
    }
    else
    {
        if ( $confirm ne 'yes' )
        {
            $status_msg = 'Media source NOT marked for deletion.';
        }
        else
        {
            $db->query( "insert into media_tags_map (tags_id, media_id) values (?, ?)", $deleteme_tags_id, $id );
            $db->query( "update media set moderated = true where media_id = ?", $medium->{ media_id } );

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
                $c->uri_for(
                    '/admin/media/moderate/' . ( $medium->{ media_id } - 1 ),
                    { status_msg => $status_msg, media_tags_id => $media_tags_id }
                )
            );
        }
    }
}

# search for media matching search for the given keyword
# return the matching media from the given page along with a
# Data::Page object for the results
sub _search_paged_media
{
    my ( $self, $c, $q, $page, $row_count ) = @_;

    my $db = $c->dbis;

    $q =~ s/^\s+//g;
    $q =~ s/\s+$//g;
    $q =~ s/[^\w]/_/g;

    $q = "'%$q%'";

    return $db->query_paged_hashes( <<END, [], $page, $row_count );
select distinct m.media_id as media_id, m.name as name, m.url as url
    from media m
        left join (
            media_tags_map mtm join (
                tags t join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id) )
            on ( mtm.tags_id = t.tags_id) )
        on (m.media_id = mtm.media_id)
    where (m.name ilike $q or m.url ilike $q or lower(ts.name||':'||t.tag) ilike $q)
    order by m.media_id
END

}

# display search form, and results of a query was submitted.
sub search : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

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
        ( $media, $pager ) = $self->_search_paged_media( $c, $q, $p, $ROWS_PER_PAGE );
    }
    elsif ( $f )
    {
        ( $media, $pager ) = $db->query_paged_hashes( <<END, [], $p, $ROWS_PER_PAGE );
select * from media m
    where not exists (select 1 from feeds f where f.media_id = m.media_id and feed_status = 'active')
    order by media_id
END
    }
    elsif ( @m )
    {
        $media = $db->query( "select * from media where media_id in (??) order by media_id", @m )->hashes;
    }
    else
    {
        ( $media, $pager ) = $db->query_paged_hashes( "select * from media order by media_id", [], $p, $ROWS_PER_PAGE );
    }

    for my $m ( @{ $media } )
    {
        $m->{ tag_names } = $db->query(
            <<"EOF",
                SELECT ts.name || ':' || t.tag
                FROM tags t, media_tags_map mtm, tag_sets ts
                WHERE t.tags_id = mtm.tags_id
                  AND t.tag_sets_id = ts.tag_sets_id
                  AND mtm.media_id = ?
EOF
            $m->{ media_id }
        )->flat;
        ( $m->{ feed_count } ) = $db->query( <<END, $m->{ media_id } )->flat;
select count(*) from feeds where media_id = ? and feed_status = 'active'
END
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

    my $db = $c->dbis;

    my $medium = $db->find_by_id( 'media', $media_id );
    if ( !$medium )
    {
        die( "Unable to find medium $media_id" );
    }

    my $action = $c->uri_for( '/admin/media/edit_tags_do/' . $media_id );

    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $media_id, 'media' );

    my $tags = $db->query( <<END, $medium->{ media_id } )->flat;
select ts.name || ':' || t.tag
    from tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
    where mtm.media_id = ?
END

    $c->stash->{ tags }     = join( ' ', @{ $tags } );
    $c->stash->{ medium }   = $medium;
    $c->stash->{ template } = 'media/edit_tags.tt2';
}

sub edit_tags_do : Local
{
    my ( $self, $c ) = @_;

    my $media_id = $c->req->params->{ media_id };

    die( "no media_id " ) unless ( $media_id );

    my $db = $c->dbis;

    my $medium = $db->find_by_id( 'media', $media_id )
      || die( "Unable to find medium $media_id" );

    my $action = $c->uri_for( '/admin/media/edit_tags_do/' ) . $media_id;
    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $media_id, 'media' );

    if ( !$form->submitted_and_valid )
    {
        return $self->edit_tags( $c, $media_id );
    }

    my $tag_names = $c->req->params->{ tags };

    MediaWords::Util::Tags::save_tags_by_name( $db, $media_id, 'media', $tag_names );

    $c->response->redirect( $c->uri_for( "/admin/feeds/list/" . $media_id, { status_msg => 'Tags updated.' } ) );
}

sub _rate_full_text_rss_likely_hood
{
    ( my $medium ) = @_;

    my $ret =
      ( $medium->{ avg_similarity } || 0 ) * 10 -
      5 * (
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

    my $db = $c->dbis;

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

        if ( $full_text_value == 1 )
        {
            $db->query( "UPDATE media set full_text_rss = true where media_id = ?", $media_id );
        }
        elsif ( $full_text_value == 0 )
        {
            $db->query( "UPDATE media set full_text_rss = false where media_id = ?", $media_id );
        }
        elsif ( $full_text_value eq '' )
        {
            $db->query( "UPDATE media set full_text_rss = NULL where media_id = ?", $media_id );
        }
        else
        {
            die "Bad case in switch :'$full_text_value'";
        }
    }

    #$db->query( "UPDATE media set full_text_rss = true where media_id in (??) ", @$media_ids );

    my $status_msg = "updated";

    #$status_msg = 'UPDATED media_ids: ' . ( join ',', @{ $media_ids } );

    #say STDERR $status_msg;

    $c->response->redirect( $c->uri_for( '/admin/media/find_likely_full_text_rss/', { status_msg => $status_msg } ) );
}

sub _get_likely_rss_full_text_media_list
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $media =
      $db->query( "select * from media_rss_full_text_detection_data natural join media where full_text_rss is null" )
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

    my $db = $c->dbis;

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
        ( $m->{ feed_count } ) = $db->query( <<END, $m->{ media_id } )->flat;
select count(*) from feeds where media_id = ? and feed_status = 'active'
END
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
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    $media_id += 0;

    my ( $medium ) = $db->query(
        <<EOF,
        SELECT *,
               media_has_active_syndicated_feeds(media_id) AS media_has_active_syndicated_feeds
        FROM media_rss_full_text_detection_data
            NATURAL JOIN media
        WHERE media_id = ?
EOF
        $media_id
    )->hashes->[ 0 ];

    $medium->{ full_text_rss_rating } = _rate_full_text_rss_likely_hood( $medium );

    #say STDERR Dumper( $medium );

    my $action = $c->uri_for( '/admin/media/do_eval_rss_full_text/' ) . $media_id;

    my $recent_stories = $db->query(
        <<EOF,
        SELECT stories.*
        FROM stories
            NATURAL JOIN downloads
            NATURAL JOIN download_texts
        WHERE media_id = ?
        ORDER BY publish_date DESC
        LIMIT 3
EOF
        $media_id
    )->hashes;

    foreach my $story ( @{ $recent_stories } )
    {
        $story->{ extracted_text } = MediaWords::DBI::Stories::get_extracted_text( $db, $story );
    }

    my $next_media_id = $self->_get_next_media_id( $c, $media_id );

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

    my $db = $c->dbis;

    my $full_text_state = $c->request->parameters->{ full_text_rss };

    die "New RSS full text value undefined " if !defined( $full_text_state );

    #say STDERR Dumper( $full_text_state );

    if ( $full_text_state ne '' )
    {
        $db->query( "UPDATE media set full_text_rss = ? where media_id = ?", $full_text_state, $id );
    }
    else
    {
        $db->query( "UPDATE media set full_text_rss = NULL where media_id = ?", $id );
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
