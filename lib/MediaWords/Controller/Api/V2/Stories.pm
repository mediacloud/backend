package MediaWords::Controller::Api::V2::Stories;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;

use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;

=head1 NAME

MediaWords::Controller::Stories - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    'default'   => 'application/json',
    'stash_key' => 'rest',
    'map'       => {

        #	   'text/html'          => 'YAML::HTML',
        'text/xml' => 'XML::Simple',

        # #         'text/x-yaml'        => 'YAML',
        'application/json'         => 'JSON',
        'text/x-json'              => 'JSON',
        'text/x-data-dumper'       => [ 'Data::Serializer', 'Data::Dumper' ],
        'text/x-data-denter'       => [ 'Data::Serializer', 'Data::Denter' ],
        'text/x-data-taxi'         => [ 'Data::Serializer', 'Data::Taxi' ],
        'application/x-storable'   => [ 'Data::Serializer', 'Storable' ],
        'application/x-freezethaw' => [ 'Data::Serializer', 'FreezeThaw' ],
        'text/x-config-general'    => [ 'Data::Serializer', 'Config::General' ],
        'text/x-php-serialization' => [ 'Data::Serializer', 'PHP::Serialization' ],
    },
);

__PACKAGE__->config( json_options => { relaxed => 1, pretty => 1, space_before => 1, space_after => 1 } );

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub _add_data_to_stories
{

    my ( $self, $db, $stories, $show_raw_1st_download ) = @_;

    foreach my $story ( @{ $stories } )
    {
        my $story_text = MediaWords::DBI::Stories::get_text_for_word_counts( $db, $story );
        $story->{ story_text } = $story_text;
    }

    foreach my $story ( @{ $stories } )
    {
        my $fully_extracted = MediaWords::DBI::Stories::is_fully_extracted( $db, $story );
        $story->{ fully_extracted } = $fully_extracted;
    }

    if ( $show_raw_1st_download )
    {
        foreach my $story ( @{ $stories } )
        {
            my $content_ref = MediaWords::DBI::Stories::get_content_for_first_download( $db, $story );

            if ( !defined( $content_ref ) )
            {
                $story->{ first_raw_download_file }->{ missing } = 'true';
            }
            else
            {

                #say STDERR "got content_ref $$content_ref";

                $story->{ first_raw_download_file } = $$content_ref;
            }
        }
    }

    foreach my $story ( @{ $stories } )
    {
        my $story_sentences =
          $db->query( "SELECT * from story_sentences where stories_id = ? ORDER by sentence_number", $story->{ stories_id } )
          ->hashes;
        $story->{ story_sentences } = $story_sentences;
    }

    foreach my $story ( @{ $stories } )
    {
        say STDERR "adding story tags ";
        my $story_tags = $db->query(
"select tags.tags_id, tags.tag, tag_sets.tag_sets_id, tag_sets.name as tag_set from stories_tags_map natural join tags natural join tag_sets where stories_id = ? ORDER by tags_id",
            $story->{ stories_id }
        )->hashes;
        $story->{ story_tags } = $story_tags;
    }

    return $stories;
}

sub single : Local : ActionClass('REST')
{
}

sub single_GET : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $query = "select s.* from stories s where stories_id = ? ";

    say STDERR "QUERY $query";

    say STDERR Dumper($c->req);

    my $stories = $c->dbis->query( $query, $stories_id )->hashes();

    my $show_raw_1st_download = $c->req->param( 'raw_1st_download' );

    $show_raw_1st_download //= 0;

    $self->_add_data_to_stories( $c->dbis, $stories, $show_raw_1st_download );

    $self->status_ok( $c, entity => $stories );
}

sub list_processed : Local : ActionClass('REST')
{
}

sub list_processed_GET : Local
{
    my ( $self, $c ) = @_;

    say STDERR "starting all_processed";

    my $last_processed_stories_id = $c->req->param( 'last_processed_stories_id' );
    say STDERR "last_processed_stories_id: $last_processed_stories_id";

    $last_processed_stories_id //= 0;

    my $show_raw_1st_download = $c->req->param( 'raw_1st_download' );

    $show_raw_1st_download //= 0;

    my $stories = $c->dbis->query(
        "select s.*, ps.processed_stories_id from stories s, processed_stories ps where s.stories_id = ps.stories_id " .
          " AND processed_stories_id > ? order by processed_stories_id  asc limit ?",
        $last_processed_stories_id, ROWS_PER_PAGE
    )->hashes;

    $self->_add_data_to_stories( $c->dbis, $stories, $show_raw_1st_download );

    $self->status_ok( $c, entity => $stories );
}

sub subset_processed : Local : ActionClass('REST')
{
}

sub subset_processed_GET : Local
{
    my ( $self, $c, $story_subsets_id ) = @_;

    my $last_processed_stories_id = $c->req->param( 'last_processed_stories_id' );

    $last_processed_stories_id //= 0;

    say STDERR "last_processed_stories_id: $last_processed_stories_id";

    my $show_raw_1st_download = $c->req->param( 'raw_1st_download' );

    $show_raw_1st_download //= 0;

    my $query =
      "select s.*, ps.processed_stories_id from stories s, processed_stories ps, story_subsets_processed_stories_map sspsm  "
      . "where s.stories_id = ps.stories_id and ps.processed_stories_id = sspsm.processed_stories_id and sspsm.story_subsets_id = ? and ps.processed_stories_id > ? "
      . "order by ps.processed_stories_id  asc limit ?";

    say STDERR "QUERY $query";

    my $stories = $c->dbis->query( $query, $story_subsets_id, $last_processed_stories_id, ROWS_PER_PAGE )->hashes();

    $self->_add_data_to_stories( $c->dbis, $stories, $show_raw_1st_download );

    $self->status_ok( $c, entity => $stories );
}

sub subset : Local : ActionClass('REST')
{
}

sub subset_PUT : Local
{
    my ( $self, $c ) = @_;
    my $subset = $c->req->data;

    my $story_subset = $c->dbis->create( 'story_subsets', $subset );

    die unless defined( $story_subset );

    $story_subset = $c->dbis->find_by_id( 'story_subsets', $story_subset->{ story_subsets_id } );

    die unless defined( $story_subset );

    $self->status_created(
        $c,
        location => $c->req->uri->as_string,
        entity   => $story_subset,
    );

}

sub subset_GET : Local
{
    my ( $self, $c, $id ) = @_;
    my $subset = $c->req->data;

    my $story_subset = $c->dbis->find_by_id( 'story_subsets', $id );

    if ( !defined( $story_subset ) )
    {
        $self->status_not_found( $c, message => "no story_subset $id", );
    }
    else
    {
        $self->status_created(
            $c,
            location => $c->req->uri->as_string,
            entity   => $story_subset,
        );
    }

}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
