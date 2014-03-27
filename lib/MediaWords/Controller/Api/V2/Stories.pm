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
use MediaWords::Solr;

=head1 NAME

MediaWords::Controller::Stories - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

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

sub has_extra_data
{
    return 1;
}

sub has_nested_data
{
    return 1;
}

sub get_table_name
{
    return "stories";
}

sub add_extra_data
{
    my ( $self, $c, $items ) = @_;

    my $show_raw_1st_download = $c->req->param( 'raw_1st_download' );

    $show_raw_1st_download //= 0;

    if ( $show_raw_1st_download )
    {
        foreach my $story ( @{ $items } )
        {
            my $content_ref = MediaWords::DBI::Stories::get_content_for_first_download( $c->dbis, $story );

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

    return $items;
}

sub _add_nested_data
{

    my ( $self, $db, $stories ) = @_;

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

        # say STDERR "story_tags";
        # say STDERR Dumper($story->{ story_tags } );
    }

    return $stories;
}

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

sub _get_list_last_id_param_name
{
    my ( $self, $c ) = @_;

    return "last_processed_stories_id";
}

sub _max_processed_stories_id
{
    my ( $self, $c ) = @_;

    my $find_max_processed_stories_id_with_postgresql = 1;

    if ( $find_max_processed_stories_id_with_postgresql )
    {
        my $hash = $c->dbis->query( "SELECT max( processed_stories_id ) from processed_stories " )->hash;

        return $hash->{ max };
    }
    else
    {
        my $params = {};

        $params->{ q } = '*:*';

        $params->{ sort } = "processed_stories_id desc";

        $params->{ rows } = 1;

        my $processed_stories_ids = MediaWords::Solr::search_for_processed_stories_ids( $params );

        my $max_processed_stories_id = $processed_stories_ids->[ 0 ];

        return $max_processed_stories_id;
    }
}

sub _get_object_ids
{
    my ( $self, $c, $last_id, $rows ) = @_;

    my $next_id = $last_id + 1;

    my $q = $c->req->param( 'q' );

    $q //= '*:*';

    my $fq = $c->req->params->{ fq };

    $fq //= [];

    if ( !ref( $fq ) )
    {
        $fq = [ $fq ];
    }

    my $processed_stories_ids = [];

    my $max_processed_stories_id = $self->_max_processed_stories_id( $c );

    say STDERR "max_processed_stories_id = $max_processed_stories_id";

    my $empty_blocks = 0;

    while ( $next_id <= $max_processed_stories_id && scalar( @$processed_stories_ids ) < $rows )
    {
        my $params = {};
        say STDERR ( Dumper( $processed_stories_ids ) );

        say STDERR ( $next_id );

        my $top_of_range = $next_id + 10_000_000;

        $params->{ q } = $q;

        $params->{ fq } = [ @{ $fq }, "processed_stories_id:[ $next_id TO $top_of_range ]" ];

        $params->{ sort } = "processed_stories_id asc";

        $params->{ rows } = $rows;

        say STDERR ( Dumper( $params ) );

        my $new_stories_ids = MediaWords::Solr::search_for_processed_stories_ids( $params );

        say STDERR Dumper( $new_stories_ids );

        if ( scalar( @{ $new_stories_ids } ) == 0 )
        {
            $empty_blocks++;

            if ( $empty_blocks > 3 )
            {
                $params->{ fq } = [ @{ $fq }, "processed_stories_id:[ $next_id TO * ]" ];
                my $remaining_sentence_matches = MediaWords::Solr::number_of_matching_documents( $params );

                if ( $remaining_sentence_matches == 0 )
                {
                    say STDERR "No remaining matches after processed_stories_id $next_id  ";
                    last;
                }
                else
                {
                    $empty_blocks = 0;
                }
            }

            $next_id = $top_of_range - 1;

        }
        else
        {
            push $processed_stories_ids, @{ $new_stories_ids };

            die unless scalar( @$processed_stories_ids );

            $next_id = $processed_stories_ids->[ -1 ] + 1;

        }
    }

    say STDERR Dumper( $processed_stories_ids );

    return $processed_stories_ids;
}

sub _fetch_list
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    my $stories_ids = $self->_get_object_ids( $c, $last_id, $rows );

    #say STDERR Dumper( $stories_ids );

    my $query =
"select stories.*, processed_stories.processed_stories_id from stories natural join processed_stories where processed_stories_id in (??) ORDER by $id_field asc ";

    my @values = @{ $stories_ids };

    return [] unless scalar( @values );

    #say STDERR Dumper( [ @values ] );

    say STDERR $query;

    my $list = $c->dbis->query( $query, @values )->hashes;

    return $list;
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

    $self->_add_tags( $c, $story_tags );

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
