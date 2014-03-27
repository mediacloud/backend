package MediaWords::Controller::Admin::Feeds;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Feed::Scrape::MediaWords;
use MediaWords::Util::Tags;
use MediaWords::Util::Web;

use Data::Dumper;
use HTML::Entities;
use LWP::Simple;
use XML::FeedPP;

=head1 NAME>

MediaWords::Controller::Feeds - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

# attach data indicating activity within feed to each feed:
# num_stories,
# most_recent_story_publish_date,
# most_recent_download_state
sub _attach_activity_data
{
    my ( $db, $feeds ) = @_;

    return unless ( @{ $feeds } );

    my $feed_story_data = $db->query( <<END, $feeds->[ 0 ]->{ media_id } )->hashes;
select count(*) num_stories, fsm.feeds_id 
    from feeds_stories_map fsm 
        join feeds f on ( f.feeds_id = fsm.feeds_id ) 
    where f.media_id = ? 
    group by fsm.feeds_id;
END

    my $feed_story_data_lookup = {};
    map { $feed_story_data_lookup->{ $_->{ feeds_id } } = $_ } @{ $feed_story_data };

    for my $feed ( @{ $feeds } )
    {
        my $fsd = $feed_story_data_lookup->{ $feed->{ feeds_id } };
        $feed->{ num_stories } = $fsd ? $fsd->{ num_stories } : 0;

        ( $feed->{ most_recent_download_state } ) = $db->query( <<END, $feed->{ feeds_id } )->flat;
select state 
    from downloads d
    where feeds_id = ? and state not in ( 'pending', 'fetching' ) 
    order by download_time desc limit 1;
END

        ( $feed->{ most_recent_story_publish_date } ) = $db->query( <<END, $feed->{ feeds_id } )->flat;
select publish_date 
    from stories s
        join feeds_stories_map fsm on ( s.stories_id = fsm.stories_id )
    where fsm.feeds_id = ? 
    order by fsm.stories_id desc limit 1;
END

    }
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

    my $sql_feed_status = $c->request->param( 'all' ) ? '1=1' : "feed_status = 'active'";

    # query the database for the list of feeds associated with the
    # given media id
    my $feeds = $c->dbis->query( <<END, $media_id )->hashes;
select * from feeds where media_id = ? and $sql_feed_status order by name, url
END

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

    # attach data indicating activity within feed to each feed
    _attach_activity_data( $c->dbis, $feeds );

    # set variables to access within the template

    # FIXME: this is too slow -hal
    $c->stash->{ showing_all_feeds } = $c->request->param( 'all' );
    $c->stash->{ medium }            = $medium;
    $c->stash->{ feeds }             = $feeds;

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

    my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;

    $media_id += 0;

    my $form =
      $self->make_edit_form( $c, $c->uri_for( '/admin/feeds/create_do/' . $media_id, { media_tags_id => $media_tags_id } ) );

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    $c->stash->{ medium }   = $medium;
    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'feeds/edit.tt2';
    $c->stash->{ title }    = 'Create ' . $medium->{ name } . ' feed';
}

# return 1 if the feed is not syndicated or does not parse as a feed
sub validate_syndicated_feed
{
    my ( $self, $c, $feed ) = @_;

    return 1 unless ( $feed->{ feed_type } eq 'syndicated' );

    eval { XML::FeedPP->new( $feed->{ url } ) };

    return ( $@ ) ? 0 : 1;
}

sub create_do : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;

    $media_id += 0;

    my $form =
      $self->make_edit_form( $c, $c->uri_for( '/admin/feeds/create_do/' . $media_id, { media_tags_id => $media_tags_id } ) );

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    if ( !$form->submitted_and_valid() )
    {
        return $self->create( $c, $media_id );
    }

    my $feed = $form->params;
    $feed->{ media_id } = $media_id;
    $feed->{ name } ||= 'feed';

    my ( $feed_exists ) = $c->dbis->query( <<END, $feed->{ media_id }, $feed->{ url } )->flat;
select 1 from feeds where media_id = ? and url = ?
END

    if ( $feed_exists )
    {
        $c->stash->{ error_msg } = 'Feed url already exists in media source';
        return $self->create( $c, $media_id );
    }

    if ( !$self->validate_syndicated_feed( $c, $feed ) )
    {
        $c->stash->{ error_msg } = 'Syndicated feed is not a valid rss/atom/rdf feed';
        return $self->create( $c, $media_id );
    }

    $feed = $c->dbis->create( 'feeds', $feed );

    if ( !$medium->{ moderated } )
    {
        $c->response->redirect(
            $c->uri_for(
                '/admin/media/moderate/' . ( $medium->{ media_id } - 1 ),
                { status_msg => 'Feed added.', media_tags_id => $media_tags_id }
            )
        );
    }
    else
    {
        $c->response->redirect(
            $c->uri_for(
                '/admin/feeds/edit_tags/' . $feed->{ feeds_id },
                { status_msg => 'Feed added.  Choose tags below.' }
            )
        );
    }
}

sub add_web_page_feed : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;

    $media_id += 0;

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    my $feed = {
        media_id  => $media_id,
        name      => $medium->{ name },
        url       => $medium->{ url },
        feed_type => 'web_page'
    };

    $feed = $c->dbis->create( 'feeds', $feed );

    $c->response->redirect(
        $c->uri_for(
            '/media/moderate/' . ( $medium->{ media_id } - 1 ),
            { status_msg => '"Web page" feed added.', media_tags_id => $media_tags_id }
        )
    );
}

sub make_scrape_form
{
    my ( $self, $c, $medium ) = @_;

    die "Undefined media source " if !$medium;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/scrape_feeds.yml',
            method           => 'post',
            action           => $c->uri_for( '/admin/feeds/scrape/' . $medium->{ media_id } )
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

        my $links =
          Feed::Scrape::MediaWords->get_valid_feeds_from_index_url( [ $url ], $recurse, $c->dbis, $ignore_patterns,
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

    $c->response->redirect( $c->uri_for( '/admin/feeds/list/' . $media_id, { status_msg => 'Feeds imported.' } ) );
}

sub edit : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    $feeds_id += 0;

    my $form = $self->make_edit_form( $c, $c->uri_for( "/admin/feeds/edit_do/$feeds_id" ) );

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

    my $form = $self->make_edit_form( $c, $c->uri_for( "/admin/feeds/edit_do/$feeds_id" ) );

    my $feed = $c->dbis->find_by_id( 'feeds', $feeds_id );

    if ( $form->submitted_and_valid )
    {

        $c->dbis->update_by_id( 'feeds', $feeds_id, $form->params );

        $c->response->redirect(
            $c->uri_for( "/admin/feeds/list/" . $feed->{ media_id }, { status_msg => 'Feed updated.' } ) );
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
        $c->response->redirect( $c->uri_for( "/admin/feeds/list/" . $medium->{ media_id }, { status_msg => $status_msg } ) );
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

        $c->response->redirect( $c->uri_for( "/admin/feeds/list/" . $medium->{ media_id }, { status_msg => $status_msg } ) );
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

    my $action = $c->uri_for( '/admin/feeds/edit_tags_do/' . $feeds_id );

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

    my $action = $c->uri_for( '/admin/feeds/edit_tags_do/' ) . $feeds_id;
    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $feeds_id, 'feeds' );

    if ( !$form->submitted_and_valid )
    {
        return $self->edit_tags( $c, $feeds_id );
    }

    MediaWords::Util::Tags->save_tags( $c, $feeds_id, 'feeds' );

    $c->response->redirect( $c->uri_for( "/admin/feeds/list/" . $feed->{ media_id }, { status_msg => 'Tags updated.' } ) );
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

    my $links = Feed::Scrape::MediaWords->get_valid_feeds_from_urls( $urls, $c->dbis );

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

    $c->response->redirect( $c->uri_for( "/admin/feeds/list/$media_id", { status_msg => $status_msg } ) );
}

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
