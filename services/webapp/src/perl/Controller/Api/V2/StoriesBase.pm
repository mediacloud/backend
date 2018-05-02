package MediaWords::Controller::Api::V2::StoriesBase;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Encode;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;

use MediaWords::DBI::Stories;
use MediaWords::Solr;
use MediaWords::Util::HTML;
use MediaWords::Util::JSON;

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
    action => {
        count       => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        word_matrix => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

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
    my $ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ stories_id } ) } @{ $stories } ] );

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

sub add_extra_data
{
    my ( $self, $c, $stories ) = @_;

    my $raw_1st_download = $c->req->params->{ raw_1st_download };

    return $stories unless ( scalar @{ $stories } && ( $raw_1st_download ) );

    my $db = $c->dbis;

    _add_raw_1st_download( $db, $stories ) if ( $raw_1st_download );

    return $stories;
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

# add a word_count field to each story that includes a word count for that story
sub _attach_word_counts_to_stories($$)
{
    my ( $db, $stories ) = @_;

    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    my ( $word_matrix, $word_list ) = MediaWords::DBI::Stories::get_story_word_matrix( $db, $stories_ids );

    while ( my ( $stories_id, $word_counts ) = each( %{ $word_matrix } ) )
    {
        while ( my ( $word_index, $count ) = each( %{ $word_counts } ) )
        {
            push(
                @{ $stories_lookup->{ $stories_id }->{ word_count } },
                {
                    stem  => $word_list->[ $word_index ]->[ 0 ],
                    term  => $word_list->[ $word_index ]->[ 1 ],
                    count => $count
                }
            );

        }
    }
}

sub _add_nested_data
{
    my ( $self, $db, $stories ) = @_;

    return [] unless ( scalar @{ $stories } );

    my $ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ stories_id } ) } @{ $stories } ] );

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
                $story_text_data->{ story_text } = MediaWords::Util::HTML::html_strip( $story_text_data->{ story_text } );
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
        my $sentences;
        $db->run_block_with_large_work_mem(
            sub {
                $sentences = $db->query(
                    <<SQL
                        SELECT *
                        FROM story_sentences
                        WHERE stories_id IN ( SELECT id FROM $ids_table )
                        ORDER BY sentence_number
SQL
                )->hashes;
            }
        );

        MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $sentences, 'story_sentences' );

    }

    if ( $self->{ show_ap_stories_id } )
    {
        my $ap_stories_ids = _get_ap_stories_ids( $db, $ids_table );

        MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $ap_stories_ids );
    }

    my $tag_data = $db->query( <<END )->hashes;
select s.stories_id::int, t.tags_id, t.tag, ts.tag_sets_id, ts.name as tag_set
    from stories_tags_map s
        join $ids_table i on ( s.stories_id = i.id )
        join tags t on ( t.tags_id = s.tags_id )
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    order by t.tags_id
END
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $tag_data, 'story_tags' );

    if ( $self->{ show_feeds } )
    {
        my $feed_data = $db->query( <<END )->hashes;
select f.name, f.url, f.media_id, f.feeds_id, f.feed_type, fsm.stories_id
    from feeds f
        join feeds_stories_map fsm using ( feeds_id )
    where
        fsm.stories_id in ( select id from $ids_table )
    order by f.feeds_id
END
        MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $feed_data, 'feeds' );
    }

    _attach_word_counts_to_stories( $db, $stories ) if ( $self->{ show_wc } );

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

    my $db = $c->dbis;

    if ( my $feeds_id = $c->req->params->{ feeds_id } )
    {
        die( "cannot specify both 'feeds_id' and either 'q' or 'fq'" )
          if ( $c->req->params->{ q } || $c->req->params->{ fq } );

        my $stories_ids = $db->query( <<SQL, $feeds_id )->flat;
select processed_stories_id from processed_stories join feeds_stories_map using ( stories_id ) where feeds_id = ?
SQL

        return $stories_ids;
    }

    my $q = $c->req->param( 'q' ) || '*:*';

    my $fq = $c->req->params->{ fq } || [];
    $fq = [ $fq ] unless ( ref( $fq ) );

    my $sort = $c->req->param( 'sort' );

    return MediaWords::Solr::search_for_processed_stories_ids( $db, $q, $fq, $last_id, $rows, $sort );
}

sub _fetch_list($$$$$$)
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    $self->{ show_sentences }     = $c->req->params->{ sentences };
    $self->{ show_text }          = $c->req->params->{ text };
    $self->{ show_ap_stories_id } = $c->req->params->{ ap_stories_id };
    $self->{ show_wc }            = $c->req->params->{ wc };
    $self->{ show_feeds }         = $c->req->params->{ show_feeds };

    $rows //= 20;
    $rows = List::Util::min( $rows, 1_000 );

    my $ps_ids = $self->_get_object_ids( $c, $last_id, $rows );

    return [] unless ( scalar @{ $ps_ids } );

    my $db = $c->dbis;

    $db->begin;

    $ps_ids = [ map { int( $_ ) } @{ $ps_ids } ];

    DEBUG( "ps_ids: " . scalar( @{ $ps_ids } ) );

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

sub count : Local : ActionClass('MC_REST')
{

}

sub count_GET
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

sub word_matrix : Local : ActionClass('MC_REST')
{

}

sub word_matrix_GET
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

    $self->status_ok( $c, entity => { word_matrix => $word_matrix, word_list => $word_list } );

}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
