package MediaWords::Controller::Feeds;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Feed::Scrape::MediaWords;
use MediaWords::Util::Tags;
use MediaWords::Util::Web;

use Data::Dumper;
use HTML::Entities;
use LWP::Simple;

=head1 NAME>

MediaWords::Controller::Feeds - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

# how many successful downloads does each feed have?
sub get_feed_download_counts
{
    my ( $self, $c, $medium ) = @_;

    return $c->dbis->query(
        "select d.feeds_id as feeds_id, count(downloads_id) as download_count from downloads d, feeds f " .
          "where f.media_id = ? grou by d.feeds_id" )->map;
}

sub list : Local
{

    # Every function that implements a page takes 'self' and 'c' as the
    # first two arguments.  Self is just a reference to the Controller::Feeds
    # object on which this method is being called, and c is a reference to
    # the object that represents the catalyst engine.  Any subsequent
    # arguments are elements in the url path used for the current
    # request, so in the below example, the url to request this
    # page looks like http://foo/feeds/list/555.  The 555 is included
    # as the final argument to this function; we treat it as the id
    # of the media source and so call it media_id.
    my ( $self, $c, $media_id ) = @_;

    # query database for the media source object corresponding to the
    # given media id.  $c->dbis is the DBIx::Simple::MediaWords db handle.
    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    # query the database for the list of feeds associated with the
    # given media id
    my $feeds = $c->dbis->query( "select * from feeds where media_id = ? order by name, url", $media_id )->hashes;

    # if there aren't any feeds, return the feed scraping page instead of
    # the feed list
    if ( !@{ $feeds } )
    {
        return $self->scrape( $c, $media_id );
    }

    # for each feed, load any other data needed for the feed within the template
    for my $f ( @{ $feeds } )
    {
        $f->{ tag_names } = $c->dbis->query(
            "select ts.name||':'||t.tag from tags t, feeds_tags_map ftm, tag_sets ts " .
              "where t.tags_id = ftm.tags_id and t.tag_sets_id = ts.tag_sets_id and ftm.feeds_id = ?",
            $f->{ feeds_id }
        )->flat;
    }

    # set variables to access within the template

    # FIXME: this is too slow -hal
    #$c->stash->{feed_download_counts} = $self->get_feed_download_counts($c, $medium);
    $c->stash->{ medium } = $medium;
    $c->stash->{ feeds }  = $feeds;

    # set the template used to generate the html.  This template can be found in mediawords/feeds/list.tt2
    $c->stash->{ template } = 'feeds/list.tt2';
}

sub make_edit_form
{
    my ( $self, $c, $action ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/feeds.yml',
            method           => 'post',
            action           => $action
        }
    );

    $form->process( $c->request );

    return $form;
}

sub create : Local
{
    my ( $self, $c, $media_id ) = @_;

    $media_id += 0;

    my $form = $self->make_edit_form( $c, $c->uri_for( '/feeds/create_do/' . $media_id ) );

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    $c->stash->{ medium }   = $medium;
    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'feeds/edit.tt2';
    $c->stash->{ title }    = 'Create ' . $medium->{ name } . ' feed';
}

sub create_do : Local
{
    my ( $self, $c, $media_id ) = @_;

    $media_id += 0;

    my $form = $self->make_edit_form( $c, $c->uri_for( '/feeds/create_do/' . $media_id ) );

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    if ( !$form->submitted_and_valid() )
    {
        return $self->create( $c, $media_id );
    }

    my $feed = $form->params;
    $feed->{ media_id } = $media_id;
    $feed->{ name } ||= 'feed';

    $feed = $c->dbis->create( 'feeds', $feed );

    if ( !$medium->{ moderated } )
    {
        $c->response->redirect(
            $c->uri_for( '/media/moderate/' . ( $medium->{ media_id } - 1 ), { status_msg => 'Feed added.' } ) );
    }
    else
    {
        $c->response->redirect(
            $c->uri_for( '/feeds/edit_tags/' . $feed->{ feeds_id }, { status_msg => 'Feed added.  Choose tags below.' } ) );
    }
}

sub make_scrape_form
{
    my ( $self, $c, $medium ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/scrape_feeds.yml',
            method           => 'post',
            action           => $c->uri_for( '/feeds/scrape/' . $medium->{ media_id } )
        }
    );

    $form->process( $c->request );

    return $form;
}

sub scrape : Local
{
    my ( $self, $c, $media_id ) = @_;

    $media_id += 0;

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    my $form = $self->make_scrape_form( $c, $medium );

    $form->get_field( 'url' )->value( $medium->{ url } );

    $c->stash->{ form }     = $form;
    $c->stash->{ medium }   = $medium;
    $c->stash->{ template } = 'feeds/scrape.tt2';

    if ( !$form->submitted_and_valid )
    {
        return;
    }
    else
    {
        my $url             = $c->request->param( 'url' );
        my $ignore_patterns = $c->request->param( 'ignore_patterns' );
        my $recurse         = $c->request->param( 'recurse' );

        my $existing_urls = [];

        my $links = Feed::Scrape::MediaWords->get_valid_feeds_from_index_url( $url, $recurse, $c->dbis, $ignore_patterns,
            $existing_urls );

        $c->stash->{ links }         = $links;
        $c->stash->{ existing_urls } = $existing_urls;
    }
}

# add default tags to scraped feed
sub add_default_scraped_tags
{
    my ( $self, $c, $feed ) = @_;

    my $content_type = 'news';
    if ( $feed->{ url } =~ /blog/ )
    {
        $content_type = 'blog';
    }

    my $tag_set = $c->dbis->find_or_create( 'tag_sets', { name => 'content_type' } );
    my $tag = $c->dbis->find_or_create( 'tags', { tag => $content_type, tag_sets_id => $tag_set->{ tag_sets_id } } );

    $c->dbis->find_or_create( 'feeds_tags_map', { tags_id => $tag->{ tags_id }, feeds_id => $feed->{ feeds_id } } );
}

sub scrape_import : Local
{
    my ( $self, $c, $media_id ) = @_;

    my @links = $c->request->param( 'links' );

    for my $link ( @links )
    {
        if ( !( $link =~ /(.*):(http:\/\/.*)/ ) )
        {
            $c->log->error( "Unable to parse scrape import link: $link" );
        }

        my $feed = $c->dbis->create(
            'feeds',
            {
                name => $1 || '(no name)',
                url => $2,
                media_id => $media_id,
            }
        );

        $self->add_default_scraped_tags( $c, $feed );
    }

    $c->response->redirect( $c->uri_for( '/feeds/list/' . $media_id, { status_msg => 'Feeds imported.' } ) );
}

sub edit : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    $feeds_id += 0;

    my $form = $self->make_edit_form( $c, $c->uri_for( "/feeds/edit_do/$feeds_id" ) );

    my $feed = $c->dbis->find_by_id( 'feeds', $feeds_id );
    $feed->{ medium } = $c->dbis->find_by_id( 'media', $feed->{ media_id } );

    $form->default_values( $feed );

    $c->stash->{ medium }   = $feed->{ medium };
    $c->stash->{ feed }     = $feed;
    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'feeds/edit.tt2';
    $c->stash->{ title }    = 'Edit ' . $feed->{ medium }->{ name } . ': ' . $feed->{ name } . ' Feed Source';
}

sub edit_do : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    my $form = $self->make_edit_form( $c, $c->uri_for( "/feeds/edit_do/$feeds_id" ) );

    my $feed = $c->dbis->find_by_id( 'feeds', $feeds_id );

    if ( $form->submitted_and_valid )
    {

        $c->dbis->update_by_id( 'feeds', $feeds_id, $form->params );

        $c->response->redirect( $c->uri_for( "/feeds/list/" . $feed->{ media_id }, { status_msg => 'Feed updated.' } ) );
    }
    else
    {

        my $medium = $c->dbis->find_by_id( 'media', $feed->{ media_id } );

        $c->stash->{ medium }   = $medium;
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'feeds/edit.tt2';
        $c->stash->{ title }    = 'Edit ' . $medium->{ name } . ': ' . $feed->{ name } . ' Feed Source ';
    }
}

sub delete : Local
{
    my ( $self, $c, $feeds_id, $confirm ) = @_;

    my $feed   = $c->dbis->find_by_id( 'feeds', $feeds_id );
    my $medium = $c->dbis->find_by_id( 'media', $feed->{ media_id } );

    my $status_msg;

    my $deleteme_tags_id = MediaWords::Util::Tags::lookup_or_create_tag( $c->dbis, 'workflow:deleteme' )->{ tags_id };

    my ( $marked_for_deletion ) =
      $c->dbis->query( "select 1 from feeds_tags_map " . "where tags_id = $deleteme_tags_id and feeds_id = ?", $feeds_id )
      ->flat;

    if ( $marked_for_deletion )
    {
        $status_msg = 'Feed already marked for deletion.';
        $c->response->redirect( $c->uri_for( "/feeds/list/" . $medium->{ media_id }, { status_msg => $status_msg } ) );
    }
    elsif ( !defined( $confirm ) )
    {

        my ( $downloads ) = $c->dbis->query( "select count(*) from downloads where feeds_id = ?",         $feeds_id )->flat;
        my ( $stories )   = $c->dbis->query( "select count(*) from feeds_stories_map where feeds_id = ?", $feeds_id )->flat;

        $c->stash->{ downloads } = $downloads;
        $c->stash->{ stories }   = $stories;

        $c->stash->{ medium }   = $medium;
        $c->stash->{ feed }     = $feed;
        $c->stash->{ template } = 'feeds/delete.tt2';
    }
    else
    {
        if ( $confirm ne 'yes' )
        {
            $status_msg = 'Feed NOT marked for deletion.';
        }
        else
        {

            $c->dbis->query( "insert into feeds_tags_map (tags_id, feeds_id) values (?, ?)", $deleteme_tags_id, $feeds_id );

            $status_msg = 'Feed marked for deletion.';
        }

        $c->response->redirect( $c->uri_for( "/feeds/list/" . $medium->{ media_id }, { status_msg => $status_msg } ) );
    }
}

sub edit_tags : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    if ( !$feeds_id )
    {
        die( "no feeds_id" );
    }

    my $feed = $c->dbis->find_by_id( 'feeds', $feeds_id );
    if ( !$feed )
    {
        die( "Unable to find feed $feeds_id" );
    }

    my $medium = $c->dbis->find_by_id( 'media', $feed->{ media_id } );

    my $action = $c->uri_for( '/feeds/edit_tags_do/' . $feeds_id );

    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $feeds_id, 'feeds' );

    $c->stash->{ form }     = $form;
    $c->stash->{ medium }   = $medium;
    $c->stash->{ template } = 'feeds/edit_tags.tt2';
}

sub edit_tags_do : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    if ( !$feeds_id )
    {
        die( "no feeds_id" );
    }

    my $feed = $c->dbis->find_by_id( 'feeds', $feeds_id );
    if ( !$feed )
    {
        die( "Unable to find feed $feeds_id" );
    }

    my $action = $c->uri_for( '/feeds/edit_tags_do/' ) . $feeds_id;
    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $feeds_id, 'feeds' );

    if ( !$form->submitted_and_valid )
    {
        return $self->edit_tags( $c, $feeds_id );
    }

    MediaWords::Util::Tags->save_tags( $c, $feeds_id, 'feeds' );

    $c->response->redirect( $c->uri_for( "/feeds/list/" . $feed->{ media_id }, { status_msg => 'Tags updated.' } ) );
}

# accept a list of feed urls and create feeds from them
sub batch_create : Local
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

    $c->stash->{ medium }   = $medium;
    $c->stash->{ template } = 'feeds/batch_create.tt2';
}

sub batch_create_do : Local
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

    my $urls = [ map { $_ =~ s/[\n\r\s]//g; $_ } split( "\n", $c->request->param( 'urls' ) ) ];

    my $links = Feed::Scrape::MediaWords->get_valid_feeds_from_urls( $urls, $c );

    for my $link ( @{ $links } )
    {
        my $feed = $c->dbis->create(
            'feeds',
            {
                media_id => $media_id,
                name     => $link->{ name } || '(no name)',
                url      => $link->{ url }
            }
        );
        $self->add_default_scraped_tags( $c, $feed );
    }

    my $status_msg;
    if ( @{ $links } < @{ $urls } )
    {
        my $skipped_urls = [
            grep {
                my $a = $_;
                !( grep { $a eq lc( $_->{ url } ) } @{ $links } )
              } @{ $urls }
        ];
        $status_msg = "The following urls were skipped: " . join( ', ', @{ $skipped_urls } );
    }
    else
    {
        $status_msg = 'All feeds were created successfully.';
    }

    $c->response->redirect( $c->uri_for( "/feeds/list/$media_id", { status_msg => $status_msg } ) );
}

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
