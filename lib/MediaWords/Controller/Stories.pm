package MediaWords::Controller::Stories;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

MediaWords::Controller::Stories - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

use constant ROWS_PER_PAGE => 100;

use MediaWords::Tagger;

# list of stories with the given feed id
sub list : Local
{

    my ( $self, $c, $feeds_id ) = @_;

    if ( !$feeds_id )
    {
        die "no feeds id";
    }

    $feeds_id += 0;

    my $p = $c->request->param( 'p' ) || 1;

    my $feed = $c->dbis->find_by_id( 'feeds', $feeds_id );
    $c->stash->{ feed } = $feed;

    my ( $stories, $pager ) = $c->dbis->query_paged_hashes(
        "select s.* from stories s, feeds_stories_map fsm where s.stories_id = fsm.stories_id " .
          "and fsm.feeds_id = $feeds_id " . "and publish_date > now() - interval '30 days' " . "order by publish_date desc",
        $p, ROWS_PER_PAGE
    );

    if ( @{ $stories } < ROWS_PER_PAGE )
    {
        ( $stories, $pager ) = $c->dbis->query_paged_hashes(
            "select s.* from stories s, feeds_stories_map fsm where s.stories_id = fsm.stories_id " .
              "and fsm.feeds_id = $feeds_id " . "order by publish_date desc",
            $p, ROWS_PER_PAGE
        );
    }

    $c->stash->{ stories }   = $stories;
    $c->stash->{ pager }     = $pager;
    $c->stash->{ pager_url } = $c->uri_for( "/stories/list/$feeds_id" ) . '?';

    $c->stash->{ template } = 'stories/list.tt2';
}

# list of stories with the given tag id
sub tag : Local
{

    my ( $self, $c, $tags_id ) = @_;

    if ( !$tags_id )
    {
        die "no tags_id";
    }

    my $tag = $c->dbis->find_by_id( 'tags', $tags_id );
    $c->stash->{ tag } = $tag;

    my $stories = $c->dbis->query(
        "select * from stories s, stories_tags_maps stm where s.stories_id = stm.stories_id and stm.tags_id = ? " .
          "order by publish_date desc",
        $tags_id
    )->hashes;

    $c->stash->{ stories } = $stories;

    $c->stash->{ template } = 'stories/tag.tt2';
}

# detail page for single story
sub view : Local
{
    my ( $self, $c, $stories_id ) = @_;

    if ( !$stories_id )
    {
        die "no stories id";
    }

    my $story = $c->dbis->find_by_id( 'stories', $stories_id );
    $c->stash->{ story } = $story;

    my @feeds = $c->dbis->query(
        "select f.* from feeds f, feeds_stories_map fsm where f.feeds_id = fsm.feeds_id and fsm.stories_id = ?",
        $stories_id )->hashes;
    $c->stash->{ feeds } = \@feeds;

    my @downloads = $c->dbis->query(
        "select d.* from downloads d where d.type = 'content' " . "    and d.state = 'success' and d.stories_id = ?",
        $stories_id )->hashes;
    $c->stash->{ downloads } = \@downloads;

    my @tags = $c->dbis->query(
        "select t.*, ts.name as tag_set_name from tags t, stories_tags_map stm, tag_sets ts " .
          "where t.tags_id = stm.tags_id and stm.stories_id = ? and t.tag_sets_id = ts.tag_sets_id " .
          "order by t.tag_sets_id",
        $stories_id
    )->hashes;
    $c->stash->{ tags } = \@tags;

    $c->stash->{ storytext } = MediaWords::DBI::Stories::get_text( $c->dbis, $story );

    $c->stash->{ stories_id } = $stories_id;

    $c->stash->{ template } = 'stories/view.tt2';
}

# delete tag
sub delete : Local
{
    my ( $self, $c, $stories_id, $tags_id, $confirm ) = @_;

    if ( $stories_id == "" || $tags_id == "" )
    {
        die "incorrectly formed link because must have Stories ID number 
        and Tags ID number. ex: stories/delete/637467/128";
    }

    my $story = $c->dbis->find_by_id( "stories", $stories_id );

    my $tag = $c->dbis->find_by_id( "tags", $tags_id );

    my $status_msg;

    if ( !defined( $confirm ) )
    {
        $c->stash->{ story }    = $story;
        $c->stash->{ tag }      = $tag;
        $c->stash->{ template } = 'stories/delete.tt2';
    }
    else
    {
        if ( $confirm ne 'yes' )
        {
            $status_msg = 'Tag NOT deleted.';
        }
        else
        {
            $c->dbis->query( "delete from stories_tags_map where tags_id = ?", $tags_id );
            $status_msg = 'Tag \'' . $tag->{ tag } . '\' deleted from this story.';
        }

        $c->response->redirect( $c->uri_for( '/stories/view/' . $story->{ stories_id }, { status_msg => $status_msg } ) );
    }
}

# sets up add tag
sub add : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $story = $c->dbis->find_by_id( "stories", $stories_id );
    $c->stash->{ story } = $story;

    my @tags =
      $c->dbis->query( "select t.* from tags t, stories_tags_map stm where t.tags_id = stm.tags_id and stm.stories_id = ?",
        $stories_id )->hashes;
    $c->stash->{ tags } = \@tags;

    my @tagsets = $c->dbis->query( "select ts.* from tag_sets ts" )->hashes;
    $c->stash->{ tagsets } = \@tagsets;

    $c->stash->{ template } = 'stories/add.tt2';
}

# executes add tag
sub add_do : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $story = $c->dbis->find_by_id( "stories", $stories_id );
    $c->stash->{ story } = $story;

    my $new_tag = $c->request->params->{ new_tag };
    if ( $new_tag eq '' )
    {
        die( "Tag NOT added.  Tag name left blank." );
    }

    my $new_tag_sets_id = $c->request->params->{ tagset };
    if ( !$new_tag_sets_id )
    {
        $new_tag_sets_id = $c->dbis->find_or_create( 'tag_sets', { name => 'manual_term' } )->{ tag_sets_id };
    }

    my $added_tag = $c->dbis->find_or_create(
        "tags",
        {
            tag         => $new_tag,
            tag_sets_id => $new_tag_sets_id,
        }
    );

    my $stm = $c->dbis->create(
        'stories_tags_map',
        {
            tags_id    => $added_tag->{ tags_id },
            stories_id => $stories_id,
        }
    );

    $c->stash->{ added_tag } = $added_tag;

    $c->response->redirect(
        $c->uri_for(
            '/stories/add/' . $story->{ stories_id },
            { status_msg => 'Tag \'' . $added_tag->{ tag } . '\' added.' }
        )
    );
}

# display regenerated tags for story
sub retag : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $story = $c->dbis->find_by_id( 'stories', $stories_id );
    my $story_text = MediaWords::DBI::Stories::get_text( $c->dbis, $story );

    my $tags = MediaWords::Tagger::get_all_tags( $story_text );

    $c->stash->{ story }      = $story;
    $c->stash->{ story_text } = $story_text;
    $c->stash->{ tags }       = $tags;
    $c->stash->{ template }   = 'stories/retag.tt2';
}

=head1 AUTHOR

Alexandra J. Sternburg

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
