package MediaWords::Controller::Api::V2::StoriesBase;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

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
use MediaWords::Util::HTML;

=head1 NAME

MediaWords::Controller::Stories - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

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

    return $stories unless ( scalar @{ $stories } && ( $raw_1st_download || $corenlp ) );

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

    $db->query( "analyze $ids_table" );

    my $ap_media_id = $db->query( "select media_id from media where name = 'Associated Press - Full Feed'" )->flat;
    return [] if ( $ap_media_id );

    my $ap_stories_ids = $db->query( <<SQL )->hashes;
with ap_sentences as
(
    select
            ss.stories_id stories_id,
            ap.stories_id ap_stories_id
        from story_sentences ss
            join story_sentences ap on ( md5( ss.sentence ) = md5( ap.sentence ) and ap.media_id = $ap_media_id )
        where
            ss.media_id <> $ap_media_id and
            ss.stories_id in ( select id from $ids_table ) and
            length( ss.sentence ) > 32
),

min_ap_sentences as
(
    select stories_id, ap_stories_id from ap_sentences group by stories_id, ap_stories_id having count(*) > 1
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

    return unless ( scalar @{ $stories } );

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    if ( $self->{ show_text } )
    {

        my $story_text_data = $db->query( <<END )->hashes;
    select s.stories_id, s.full_text_rss,
            case when BOOL_AND( s.full_text_rss ) then s.title || E'.\n\n' || s.description
                else string_agg( dt.download_text, E'.\n\n'::text )
            end story_text
        from stories s
            join downloads d on ( s.stories_id = d.stories_id )
            left join download_texts dt on ( d.downloads_id = dt.downloads_id )
        where s.stories_id in ( select id from $ids_table )
        group by s.stories_id
END

        for my $story_text_data ( @$story_text_data )
        {
            if ( $story_text_data->{ full_text_rss } )
            {
                $story_text_data->{ story_text } = html_strip( $story_text_data->{ story_text } );
            }
        }

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

    # Bit.ly total click counts
    my $bitly_click_data = $db->query(
        <<"EOF",
        -- Return NULL for where click count is not yet present
        SELECT $ids_table.id AS stories_id,
               bitly_clicks_total.click_count AS bitly_click_count
        FROM $ids_table
            LEFT JOIN bitly_clicks_total
                ON $ids_table.id = bitly_clicks_total.stories_id
EOF
    )->hashes;
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $bitly_click_data );

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

    my $sort = $c->req->param( 'sort' );

    return MediaWords::Solr::search_for_processed_stories_ids( $c->dbis, $q, $fq, $last_id, $rows, $sort );
}

sub _fetch_list($$$$$$)
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    $self->{ show_sentences }     = $c->req->params->{ sentences };
    $self->{ show_text }          = $c->req->params->{ text };
    $self->{ show_ap_stories_id } = $c->req->params->{ ap_stories_id };

    $rows //= 20;
    $rows = List::Util::min( $rows, 10_000 );

    my $ps_ids = $self->_get_object_ids( $c, $last_id, $rows );

    return [] unless ( scalar @{ $ps_ids } );

    my $db = $c->dbis;

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( $ps_ids, 1 );

    my $stories = $db->query(
        <<"SQL",
        WITH ps_ids AS (

            SELECT ${ids_table}_pkey order_pkey,
                   id AS processed_stories_id,
                   processed_stories.stories_id
            FROM $ids_table
                INNER JOIN processed_stories
                    ON $ids_table.id = processed_stories.processed_stories_id
        )

        SELECT stories.*,
               ps_ids.processed_stories_id,
               media.name AS media_name,
               media.url AS media_url,
               coalesce( ap.ap_syndicated, false ) as ap_syndicated
        FROM ps_ids
            JOIN stories
                ON ps_ids.stories_id = stories.stories_id
            JOIN media
                ON stories.media_id = media.media_id
            LEFT JOIN stories_ap_syndicated ap
                ON stories.stories_id = ap.stories_id
        ORDER BY ps_ids.order_pkey
        LIMIT ?
SQL
        $rows
    )->hashes;

    $db->commit;

    return $stories;
}

sub count : Local : ActionClass('REST')
{

}

sub count_GET : Local
{
    my ( $self, $c ) = @_;

    my $q  = $c->req->params->{ 'q' };
    my $fq = $c->req->params->{ 'fq' };

    my $response;
    my $list = MediaWords::Solr::query( $c->dbis,
        { q => $q, fq => $fq, group => "true", "group.field" => "stories_id", "group.ngroups" => "true" }, $c );
    $response = { count => $list->{ grouped }->{ stories_id }->{ ngroups } };

    $self->status_ok( $c, entity => $response );
}

sub word_matrix : Local : ActionClass('REST')
{

}

sub word_matrix_GET : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $q    = $c->req->params->{ q };
    my $fq   = $c->req->params->{ fq };
    my $rows = $c->req->params->{ rows } || 1000;

    die( "must specify either 'q' or 'fq' param" ) unless ( $q || $fq );

    $rows = List::Util::min( $rows, 100_000 );

    my $stories_ids =
      MediaWords::Solr::search_for_stories_ids( $db, { q => $q, fq => $fq, rows => $rows, sort => 'random_1 asc' } );

    my ( $word_matrix, $word_list ) = MediaWords::DBI::Stories::get_story_word_matrix( $db, $stories_ids );

    $self->status_ok( $c, entity => [ word_matrix => $word_matrix, word_list => $word_list ] );

}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
