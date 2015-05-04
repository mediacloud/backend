package MediaWords::Controller::Api::V2::StoriesBase;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Encode;
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;

use MediaWords::DBI::Stories;
use MediaWords::Solr;
use MediaWords::Util::CoreNLP;

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

# for each story, add the content of the raw 1st download associated with that story
# to the { raw_first_download_file } field.
sub _add_raw_1st_download
{
    my ( $db, $stories ) = @_;

    $db->begin;
    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

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
}

# for each story, add the corenlp anno
sub _add_corenlp
{
    my ( $db, $stories, $ids_table ) = @_;

    die( "corenlp annotator is not enabled" ) unless ( MediaWords::Util::CoreNLP::annotator_is_enabled );

    for my $story ( @{ $stories } )
    {
        my $stories_id = $story->{ stories_id };

        if ( !MediaWords::Util::CoreNLP::story_is_annotated( $db, $stories_id ) )
        {
            $story->{ corenlp } = { annotated => 'false' };
            next;
        }

        my $json = MediaWords::Util::CoreNLP::fetch_annotation_json_for_story_and_all_sentences( $db, $stories_id );

        my $json_data = decode_json( encode( 'utf8', $json ) );

        die( "unable to parse corenlp json for story '$stories_id'" )
          unless ( $json_data && $json_data->{ _ }->{ corenlp } );

        $story->{ corenlp } = $json_data;
    }
}

sub add_extra_data
{
    my ( $self, $c, $stories ) = @_;

    my $raw_1st_download = $c->req->params->{ raw_1st_download };
    my $corenlp          = $c->req->params->{ corenlp };

    return $stories unless ( @{ $stories } && ( $raw_1st_download || $corenlp ) );

    my $db = $c->dbis;

    _add_raw_1st_download( $db, $stories ) if ( $raw_1st_download );

    _add_corenlp( $db, $stories ) if ( $corenlp );

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

# give the story ids in $ids_table, query the db for a list of stories_ids each with an
# ap_stories_id present if the story is syndicated from some ap story
sub _get_ap_stories_ids
{
    my ( $db, $ids_table ) = @_;

    my $ap_stories_ids = $db->query( <<SQL )->hashes;
with ap_sentences as
(
    select
            ssc.first_stories_id stories_id,
            ap.first_stories_id ap_stories_id
        from story_sentence_counts ssc
            join story_sentence_counts ap on ( ssc.sentence_md5 = ap.sentence_md5 )
        where
            ssc.first_stories_id in ( select id from $ids_table ) and
            ssc.first_stories_id <> ap.first_stories_id and

            -- the following exists is to make postgres avoid a bad query plan
            exists (
                select 1 from media m where m.name = 'Associated Press - Full Feed' and ap.media_id = m.media_id
            ) and

            -- we don't want to join story_sentences other than for the small
            -- number of sentences that have some match
            exists (
                select 1
                    from story_sentences ss
                    where
                        ss.stories_id = ssc.first_stories_id and
                        ss.sentence_number = ssc.first_sentence_number and
                        length( ss.sentence ) > 32
            )
),

min_ap_sentences as
(
    select stories_id, ap_stories_id from ap_sentences group by stories_id, ap_stories_id having count(*) > 3
)

select ids.id stories_id, ap.ap_stories_id
    from $ids_table ids
        left join min_ap_sentences ap on ( ids.id = ap.stories_id )
SQL

    return $ap_stories_ids;
}

sub _add_nested_data
{
    my ( $self, $db, $stories ) = @_;

    return unless ( @{ $stories } );

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    if ( $self->{ show_text } )
    {

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
    }

    if ( $self->{ show_sentences } )
    {
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
    }

    if ( $self->{ show_ap_stories_id } )
    {
        my $ap_stories_ids = _get_ap_stories_ids( $db, $ids_table );

        MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $ap_stories_ids );
    }

    my $tag_data = $db->query( <<END )->hashes;
select s.stories_id, t.tags_id, t.tag, ts.tag_sets_id, ts.name as tag_set
    from stories_tags_map s
        join tags t on ( t.tags_id = s.tags_id )
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where s.stories_id in ( select id from $ids_table )
    order by t.tags_id
END
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $tag_data, 'story_tags' );

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

    return MediaWords::Solr::search_for_processed_stories_ids( $c->dbis, $q, $fq, $last_id, $rows );
}

sub _fetch_list
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    $self->{ show_sentences }     = $c->req->params->{ sentences };
    $self->{ show_text }          = $c->req->params->{ text };
    $self->{ show_ap_stories_id } = $c->req->params->{ ap_stories_id };

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
