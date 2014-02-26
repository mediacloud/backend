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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

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

sub single : Local : ActionClass('+MediaWords::Controller::Api::V2::MC_Action_REST')
{
}

sub single_GET : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $query = "select s.* from stories s where stories_id = ? ";

    say STDERR "QUERY $query";

    say STDERR Dumper( $c->req );

    my $stories = $c->dbis->query( $query, $stories_id )->hashes();

    my $show_raw_1st_download = $c->req->param( 'raw_1st_download' );

    $show_raw_1st_download //= 0;

    $self->_add_data_to_stories( $c->dbis, $stories, $show_raw_1st_download );

    $self->status_ok( $c, entity => $stories );
}

sub list_processed : Local : ActionClass('+MediaWords::Controller::Api::V2::MC_Action_REST')
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


sub _add_story_tags
{
    my ( $self, $c, $story_tags ) = @_;

    foreach my $story_tag ( @$story_tags )
    {
        say STDERR "story_tag $story_tag";

        my ( $stories_id, $tag) = split ',', $story_tag;
	
	my $tags_id = $tag;

	say STDERR "$stories_id, $tags_id";

	$c->dbis->query( "INSERT INTO stories_tags_map( stories_id, tags_id) VALUES (?, ? )", $stories_id, $tags_id );
    }
}

sub put_tags : Local : ActionClass('+MediaWords::Controller::Api::V2::MC_Action_REST')
{
}

sub put_tags_PUT : Local
{
    my ( $self, $c ) = @_;
    my $subset = $c->req->data;


    my $story_tag = $c->req->params->{ 'story_tag' };

    my $story_tags;

    if ( ref $story_tag )
    {
       $story_tags = $story_tag;
    }
    else
    {
       $story_tags = [ $story_tag ];
    }

    say STDERR Dumper( $story_tags );

    $self->_add_story_tags( $c, $story_tags );

    $self->status_ok( $c, entity => $story_tags );

    return;
}


=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
