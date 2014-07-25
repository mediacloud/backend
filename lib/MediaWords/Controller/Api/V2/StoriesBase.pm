package MediaWords::Controller::Api::V2::StoriesBase;
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

    return $stories unless ( @{ $stories } && ( $c->req->param( 'raw_1st_download' ) ) );

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

# the story_sentences query returns story_sentences_tags as a ; separated list.
# this function splits the tags_list field of each sentence into a proper list
# and reassigns the result to the tags field.  the tags_list field is deleted
# after splitting.
sub _split_sentence_tags_list
{
    my ( $stories ) = @_;

    for my $story ( @{ $stories } )
    {
        for my $ss ( @{ $story->{ story_sentences } } )
        {
            $ss->{ tags } = [ split( ';', $ss->{ tags_list } || '' ) ];
            delete( $ss->{ tags_list } );
        }
    }
}

sub _add_nested_data
{
    my ( $self, $db, $stories, $show_raw_1st_download ) = @_;

    return unless ( @{ $stories } );

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
select s.*, string_agg( sstm.tags_id::text, ';' ) tags_list
    from story_sentences s
        left join story_sentences_tags_map sstm on ( s.story_sentences_id = sstm.story_sentences_id )
    where s.stories_id in ( select id from $ids_table )
    group by s.story_sentences_id
    order by s.sentence_number
END
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $sentences, 'story_sentences' );

    _split_sentence_tags_list( $stories );

    my $tag_data = $db->query( <<END )->hashes;
select s.stories_id, t.tags_id, t.tag, ts.tag_sets_id, ts.name as tag_set 
    from stories_tags_map s
        join tags t on ( t.tags_id = s.tags_id )
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where s.stories_id in ( select id from $ids_table )
    order by t.tags_id
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

sub _get_object_ids
{
    my ( $self, $c, $last_id, $rows ) = @_;

    my $q = $c->req->param( 'q' ) || '*:*';

    my $fq = $c->req->params->{ fq } || [];
    $fq = [ $fq ] unless ( ref( $fq ) );

    return MediaWords::Solr::search_for_processed_stories_ids( $q, $fq, $last_id, $rows );
}

sub _fetch_list
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    $rows //= 20;
    $rows = List::Util::min( $rows, 10_000 );

    my $ps_ids = $self->_get_object_ids( $c, $last_id, $rows );

    return [] unless ( @{ $ps_ids } );

    my $db = $c->dbis;

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( $ps_ids );

    my $stories = $db->query( <<END )->hashes;
with ps_ids as

    ( select processed_stories_id, stories_id 
        from processed_stories
        where processed_stories_id in ( select id from $ids_table ) )

select s.*, p.processed_stories_id, m.name media_name, m.url media_url
    from stories s join ps_ids p on ( s.stories_id = p.stories_id )
    join media m on ( s.media_id = m.media_id )
    order by processed_stories_id asc limit $rows
END

    $db->commit;

    return $stories;
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
