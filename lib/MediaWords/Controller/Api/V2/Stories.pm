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

use MediaWords::DBI::Stories;
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
    my ( $self, $c, $stories ) = @_;

    return $stories unless ( $c->req->param( 'raw_1st_download' ) );

    my $db = $c->dbis;

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    # it's a bit confusing to use this function to attach data to downloads,
    # but it works b/c w want one download per story
    my $downloads = $db->query( <<END )->hashes;
select d.* 
    from downloads d
        join (
            select min( s.downloads_id ) over ( partition by s.stories_id ) downloads_id
                from downloads s
                where s.stories_id in ( select id from $ids_table )
        ) q on ( d.downloads_id = q.downloads_id )
END

    my $story_lookup = {};
    map { $story_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    for my $download ( @{ $downloads } )
    {
        my $story = $story_lookup->{ $download->{ stories_id } };
        my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );

        $story->{ raw_first_download_file } = defined( $content_ref ) ? $$content_ref : { missing => 'true' };
    }

    $db->commit;

    return $stories;
}

sub _add_nested_data
{
    my ( $self, $db, $stories, $show_raw_1st_download ) = @_;

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    my $story_text_data = $db->query( <<END )->hashes;
select s.stories_id,
        case when BOOL_AND( m.full_text_rss ) then s.description
            else string_agg( dt.download_text, E'.\n\n' )
        end story_text
    from stories s
        join media m on ( s.media_id = m.media_id )
        join downloads d on ( s.stories_id = d.stories_id )
        left join download_texts dt on ( d.downloads_id = dt.downloads_id )
    where s.stories_id in ( select id from $ids_table )
    group by s.stories_id
END
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $story_text_data );

    my $extracted_data = $db->query( <<END )->hashes;
select s.stories_id,
        BOOL_AND( extracted ) is_fully_extracted
    from stories s
        join downloads d on ( s.stories_id = d.stories_id )
    where s.stories_id in ( select id from $ids_table )
    group by s.stories_id
END
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $extracted_data );

    my $sentences = $db->query( <<END )->hashes;
select s.* 
    from story_sentences s
    where s.stories_id in ( select id from $ids_table )
    order by s.sentence_number
END
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $sentences, 'story_sentences' );

    my $tag_data = $db->query( <<END )->hashes;
select s.stories_id, tags.tags_id, tags.tag, tag_sets.tag_sets_id, tag_sets.name as tag_set 
    from stories_tags_map s
        natural join tags 
        natural join tag_sets 
    where s.stories_id in ( select id from $ids_table )
    order by tags_id
END
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $tag_data, 'story_tags' );

    $db->commit;

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
        return MediaWords::Solr::max_processed_stories_id( $c->dbis );
    }
}

sub _get_object_ids
{
    my ( $self, $c, $last_id, $rows ) = @_;

    my $db = $c->dbis;

    my $q = $c->req->param( 'q' );

    $q //= '*:*';

    my $fq = $c->req->params->{ fq };

    $fq //= [];

    if ( !ref( $fq ) )
    {
        $fq = [ $fq ];
    }

    my $processed_stories_ids = [];

    my $next_id = $last_id ? $last_id + 1 : MediaWords::Solr::min_processed_stories_id( $c->dbis, { q => $q, fq => $fq } );

    return [] unless ( $next_id );

    my $max_processed_stories_id = $self->_max_processed_stories_id( $c );

    # say STDERR "max_processed_stories_id = $max_processed_stories_id";

    my $empty_blocks = 0;
    my $num_solr_searches;
    my $exp_search_growth = 1;
    my $exp_rows_growth   = 1;

    while ( $next_id <= $max_processed_stories_id && scalar( @$processed_stories_ids ) < $rows )
    {
        my $params = {};

        my $top_of_range = $next_id + 50_000;

        # print STDERR "top_of_range: $top_of_range [ $num_solr_searches ]\n";

        $params->{ q } = $q;

        $params->{ fq } = [ @{ $fq }, "processed_stories_id:[ $next_id TO $top_of_range ]" ];

        $params->{ sort } = "processed_stories_id asc";

        $params->{ rows } = $rows * $exp_rows_growth;

        # say STDERR ( Dumper( $params ) );

        my $new_stories_ids = MediaWords::Solr::search_for_processed_stories_ids( $db, $params );

        # say STDERR Dumper( $new_stories_ids );

        if ( ( scalar( @{ $new_stories_ids } ) == 0 ) )
        {
            my $next_fq = [ @{ $fq }, "processed_stories_id:[ $next_id TO * ]" ];
            $next_id = MediaWords::Solr::min_processed_stories_id( $c->dbis, { q => $q, fq => $next_fq } );
            last unless ( $next_id );
        }
        else
        {
            push $processed_stories_ids, @{ $new_stories_ids };
            $next_id = $processed_stories_ids->[ -1 ] + 1;

            if ( $next_id < $top_of_range )
            {
                $exp_rows_growth *= 2;
            }
        }
    }

    # say STDERR Dumper( $processed_stories_ids );

    return $processed_stories_ids;
}

sub _fetch_list
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    $rows //= 20;
    $rows = List::Util::min( $rows, 10_000 );

    my $stories_ids = $self->_get_object_ids( $c, $last_id, $rows );

    return [] unless ( @{ $stories_ids } );

    my $db = $c->dbis;

    my $stories;
    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( $stories_ids );

    $stories = $db->query( <<END )->hashes;
select s.*, max( ps.processed_stories_id ) processed_stories_id
    from stories s 
        natural join processed_stories ps
    where ps.processed_stories_id in ( select id from $ids_table )
    group by s.stories_id 
    order by $id_field asc limit $rows
END

    $db->commit;

    return $stories;
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

    # say STDERR Dumper( $story_tags );

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
