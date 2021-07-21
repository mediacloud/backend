package MediaWords::Controller::Api::V2::StoriesBase;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use List::MoreUtils qw(natatime);
use List::Util;
use Moose;
use namespace::autoclean;

use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::WordMatrix;
use MediaWords::DBI::Stories::WordMatrixOldStopwords;   # FIXME remove once stopword comparison is over
use MediaWords::Solr;
use MediaWords::Solr::TagCounts;
use MediaWords::Util::ParseHTML;
use MediaWords::DBI::Downloads::Store;

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
        tag_count   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
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

    my $ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ stories_id } ) } @{ $stories } ] );

    my $downloads = $db->query( <<"SQL"
            SELECT DISTINCT ON(stories_id) *
            FROM downloads
            WHERE stories_id IN (
                SELECT id
                FROM $ids_table
            )
            ORDER BY
                stories_id,
                downloads_id
SQL
    )->hashes;

    my $story_lookup = {};
    map { $story_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    for my $download ( @{ $downloads } )
    {
        my $story = $story_lookup->{ $download->{ stories_id } };

        my $content = undef;
        eval {
            $content = MediaWords::DBI::Downloads::Store::fetch_content( $db, $download );
        };
        if ( $@ ) {
            my $downloads_id = $download->{ downloads_id };
            my $stories_id = $download->{ stories_id };

            # The download might just not exist on S3 due to historical data losses and such
            WARN "Unable to fetch content for download $downloads_id for story $stories_id: $@";
        }

        $story->{ raw_first_download_file } = defined( $content ) ? $content : { missing => 'true' };
    }
}

sub add_extra_data
{
    my ( $self, $c, $stories ) = @_;

    my $raw_1st_download = int( $c->req->params->{ raw_1st_download } // 0 );

    return $stories unless ( scalar @{ $stories } && ( $raw_1st_download ) );

    my $db = $c->dbis;

    _add_raw_1st_download( $db, $stories ) if ( $raw_1st_download );

    return $stories;
}

# give the story ids in $ids_list, query the db for a list of stories_ids each with an
# ap_stories_id present if the story is syndicated from some ap story
sub _get_ap_stories_ids
{
    my ( $db, $ids_list ) = @_;

    my $ap_media_id = $db->query( <<SQL
        SELECT media_id
        FROM media
        WHERE name = 'Associated Press - Full Feed'
SQL
    )->flat;
    return [] if ( $ap_media_id );

    my $ap_stories_ids = $db->query(
        <<SQL

        WITH ap_sentences AS (
            SELECT
                ss.stories_id AS stories_id,
                ap.stories_id AS ap_stories_id
            FROM story_sentences AS ss
                INNER JOIN story_sentences AS ap ON
                    md5(ss.sentence) = md5(ap.sentence) AND
                    ap.media_id = $ap_media_id
            WHERE
                ss.media_id != $ap_media_id AND
                ss.stories_id IN ($ids_list) AND
                LENGTH(ss.sentence) > 32
        ),

        min_ap_sentences AS (
            SELECT
                stories_id,
                ap_stories_id
            FROM ap_sentences
            GROUP BY
                stories_id,
                ap_stories_id
            HAVING COUNT(*) > 1
        )

        SELECT
            stories_id,
            ap_stories_id
        FROM min_ap_sentences AS ap
        WHERE stories_id in ( $ids_list )
SQL
    )->hashes;

    return $ap_stories_ids;
}

# add a word_count field to each story that includes a word count for that story
# FIXME remove extra "$" once stopword comparison is over
sub _attach_word_counts_to_stories($$$)
{
    # FIXME remove extra parameter once stopword comparison is over
    my ( $db, $stories, $old_stopwords ) = @_;

    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    my ( $word_matrix, $word_list );
    if ( $old_stopwords ) {
        ( $word_matrix, $word_list ) = MediaWords::DBI::Stories::WordMatrixOldStopwords::get_story_word_matrix( $db, $stories_ids );
    } else {
        ( $word_matrix, $word_list ) = MediaWords::DBI::Stories::WordMatrix::get_story_word_matrix( $db, $stories_ids );
    }

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

    return $stories;
}

sub _add_nested_data
{
    my ( $self, $db, $stories ) = @_;

    return [] unless ( scalar @{ $stories } );

    my $ids_list = join( ',', map { int( $_->{ stories_id } ) } @{ $stories } );

    if ( int( $self->{ show_text } // 0 ) )
    {

        my $story_text_data = $db->query( <<SQL

            WITH story_download_texts AS (
                SELECT
                    downloads_success.downloads_id,
                    downloads_success.stories_id,
                    download_texts.download_texts_id,
                    download_texts.download_text
                FROM downloads_success
                    LEFT JOIN download_texts ON
                        downloads_success.downloads_id = download_texts.downloads_id
                WHERE downloads_success.stories_id IN ($ids_list)
            )

            SELECT
                stories.stories_id,
                stories.full_text_rss,
                CASE
                    WHEN BOOL_AND(stories.full_text_rss) THEN stories.title || E'.\n\n' || stories.description
                    ELSE string_agg(story_download_texts.download_text, E'.\n\n'::TEXT)
                END AS story_text
            FROM stories
                INNER JOIN story_download_texts ON
                    stories.stories_id = story_download_texts.stories_id
            WHERE stories.stories_id IN ($ids_list)
            GROUP BY stories.stories_id

SQL
        )->hashes;

        for my $story_text_data ( @$story_text_data )
        {
            if ( $story_text_data->{ full_text_rss } )
            {
                $story_text_data->{ story_text } = MediaWords::Util::ParseHTML::html_strip(
                    $story_text_data->{ story_text }
                );
            }
        }

        $stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $story_text_data );

        my $extracted_data = $db->query(
            <<SQL
            SELECT
                stories_id,
                BOOL_AND(extracted) AS is_fully_extracted
            FROM downloads_success
            WHERE stories_id IN ($ids_list)
            GROUP BY stories_id
SQL
        )->hashes;

        $stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $extracted_data );
    }

    if ( int( $self->{ show_sentences } // 0 ) )
    {
        my $sentences = $db->query(
            <<SQL
            SELECT *
            FROM story_sentences
            WHERE stories_id IN ($ids_list)
            ORDER BY sentence_number
SQL
        )->hashes;

        $stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $sentences, 'story_sentences' );

    }

    if ( int( $self->{ show_ap_stories_id } // 0 ) )
    {
        my $ap_stories_ids = _get_ap_stories_ids( $db, $ids_list );

        $stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $ap_stories_ids );
    }

    my $iter = natatime(100, @{ $stories } );
    while ( my @chunk_stories = $iter->() )
    {
        my $chunk_ids_list = join( ',', map { int( $_->{ stories_id } ) } @chunk_stories );
        my $tag_data = $db->query( <<SQL
            SELECT
                stories_tags_map.stories_id,
                tags.tags_id,
                tags.tag,
                tag_sets.tag_sets_id,
                tag_sets.name AS tag_set
            FROM stories_tags_map
                INNER JOIN tags ON
                    tags.tags_id = stories_tags_map.tags_id
                INNER JOIN tag_sets ON
                    tag_sets.tag_sets_id = tags.tag_sets_id
            WHERE stories_tags_map.stories_id IN ($chunk_ids_list)
            ORDER BY tags.tags_id
SQL
        )->hashes;

        $stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $tag_data, 'story_tags' );
    }

    if ( int( $self->{ show_feeds } // 0 ) )
    {
        my $feed_data = $db->query( <<SQL

            WITH story_feed_ids AS (
                SELECT
                    stories_id,
                    feeds_id
                FROM feeds_stories_map
                WHERE stories_id IN ($ids_list)
            )

            SELECT
                feeds.name,
                feeds.url,
                feeds.media_id,
                feeds.feeds_id,
                feeds.type,
                story_feed_ids.stories_id
            FROM story_feed_ids
                INNER JOIN feeds ON
                    story_feed_ids.feeds_id = feeds.feeds_id
            ORDER BY story_feed_ids.feeds_id

SQL
        )->hashes;

        $stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $feed_data, 'feeds' );
    }

    if ( int( $self->{ show_wc } // 0 ) ) {
        $stories = _attach_word_counts_to_stories( $db, $stories, $self->{ old_stopwords } );
    }

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

    if ( my $feeds_id = int( $c->req->params->{ feeds_id } // 0 ) )
    {
        die( "cannot specify both 'feeds_id' and either 'q' or 'fq'" )
          if ( $c->req->params->{ q } || $c->req->params->{ fq } );

        my $stories_ids = $db->query( <<SQL,
            SELECT processed_stories.processed_stories_id
            FROM feeds_stories_map
                INNER JOIN processed_stories ON
                    feeds_stories_map.stories_id = processed_stories.stories_id
            WHERE feeds_stories_map.feeds_id = ?
            ORDER BY feeds_stories_map.stories_id DESC
            LIMIT ?
SQL
            $feeds_id, $rows
        )->flat;

        return $stories_ids;
    }

    my $q = $c->req->param( 'q' ) || '*:*';

    my $fq = $c->req->params->{ fq } || [];
    $fq = [ $fq ] unless ( ref( $fq ) );

    my $sort_by_random = 0;
    if ( $c->req->param( 'sort' ) eq 'random' ) {
        $sort_by_random = 1;
    }

    return MediaWords::Solr::search_solr_for_processed_stories_ids( $db, $q, $fq, $last_id, $rows, $sort_by_random );
}

sub _fetch_list($$$$$$)
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    $self->{ show_sentences }     = int( $c->req->params->{ sentences }     // 0 );
    $self->{ show_text }          = int( $c->req->params->{ text }          // 0 );
    $self->{ show_ap_stories_id } = int( $c->req->params->{ ap_stories_id } // 0 );
    $self->{ show_wc }            = int( $c->req->params->{ wc }            // 0 );
    # FIXME remove once stopword comparison is over
    $self->{ old_stopwords }      = int( $c->req->params->{ old_stopwords } // 0 );
    $self->{ show_feeds }         = int( $c->req->params->{ show_feeds }    // 0 );

    $rows //= 20;
    $rows = List::Util::min( $rows, 1_000 );

    my $ps_ids = $self->_get_object_ids( $c, $last_id + 0, $rows );

    return [] unless ( scalar @{ $ps_ids } );

    my $db = $c->dbis;

    $db->begin;

    $ps_ids = [ map { int( $_ ) } @{ $ps_ids } ];

    DEBUG( "ps_ids: " . scalar( @{ $ps_ids } ) );

    my $ids_table = $db->get_temporary_ids_table( $ps_ids, 1 );

    my $order_clause = $c->req->params->{ feeds_id } ? 'stories_id DESC' : 'order_pkey ASC';

    my $stories = $db->query( <<"SQL",
        WITH ps_ids AS (

            SELECT
                ${ids_table}_pkey AS order_pkey,
                id AS processed_stories_id,
                processed_stories.stories_id
            FROM $ids_table
                INNER JOIN processed_stories
                    ON $ids_table.id = processed_stories.processed_stories_id
            ORDER BY $order_clause
            LIMIT ?
        )

        SELECT
            stories.*,
            ps_ids.processed_stories_id,
            media.name AS media_name,
            media.url AS media_url,
            COALESCE(ap.ap_syndicated, false) AS ap_syndicated
        FROM ps_ids
            INNER JOIN stories ON
                ps_ids.stories_id = stories.stories_id
            INNER JOIN media ON
                stories.media_id = media.media_id
            LEFT JOIN stories_ap_syndicated ap ON
                stories.stories_id = ap.stories_id

        ORDER BY $order_clause
SQL
        $rows
    )->hashes;

    $db->commit;

    return $stories;
}

# execute a query on solr and return a list of dates with a count of stories for each date
sub _get_date_counts
{
    my ( $self, $c ) = @_;

    my $q            = $c->req->params->{ 'q' };
    my $fq           = $c->req->params->{ 'fq' };
    my $split_period = lc( $c->req->params->{ 'split_period' } || 'day' );

    die( "Unknown split_period '$split_period'" ) unless ( grep { $_ eq $split_period } qw/day week month year/ );

    my $facet_field = "publish_$split_period";

    my $json_facet = <<END;
{categories:{sort: index, type:terms, field: publish_$split_period, limit: 1000000, facet:{x:"hll(stories_id)"}}}
END

    my $params;
    $params->{ q }            = $q;
    $params->{ fq }           = $fq;
    $params->{ rows }         = 0;
    $params->{ 'json.facet' } = $json_facet;

    my $solr_response = MediaWords::Solr::query_solr( $c->dbis, $params );

    my $facet_counts = $solr_response->{ facets }->{ categories }->{ buckets };

    my $date_counts = [];
    for my $facet_count ( @{ $facet_counts } )
    {
        my $date = $facet_count->{ val };
        my $count = $facet_count->{ x };

        $date =~ s/(.*)T(.*)Z$/$1 $2/;
        push( @{ $date_counts }, { date => $date, count => $count } );
    }

    return $date_counts;
}

sub count : Local : ActionClass('MC_REST')
{

}

sub count_GET
{
    my ( $self, $c ) = @_;

    my $q     = $c->req->params->{ 'q' };
    my $fq    = $c->req->params->{ 'fq' };
    my $split = $c->req->params->{ 'split' };

    my $response;
    if ( $split )
    {
        my $date_counts = $self->_get_date_counts( $c, $c->req->params );
        $response = { counts => $date_counts };
    }
    else
    {
        my $num_found = MediaWords::Solr::get_solr_num_found( $c->dbis, { q => $q, fq => $fq } );
        $response = { count => $num_found };
    }

    $self->status_ok( $c, entity => $response );
}

sub tag_count : Local : ActionClass('MC_REST')
{
}

sub tag_count_GET
{
    my ( $self, $c ) = @_;

    my $tag_counts = MediaWords::Solr::TagCounts::query_tag_counts( $c->dbis, $c->req->params );

    $self->status_ok( $c, entity => $tag_counts );
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
    my $rows = int( $c->req->params->{ rows } // 1000 );

    die( "must specify either 'q' or 'fq' param" ) unless ( $q || $fq );

    $rows = List::Util::min( $rows, 100_000 );

    my $stories_ids =
      MediaWords::Solr::search_solr_for_stories_ids( $db, { q => $q, fq => $fq, rows => $rows, sort => 'random_1 asc' } );

    my ( $word_matrix, $word_list );
    if ( $c->req->params->{ old_stopwords } ) {
        # FIXME remove once stopword comparison is over
        ( $word_matrix, $word_list ) = MediaWords::DBI::Stories::WordMatrixOldStopwords::get_story_word_matrix( $db, $stories_ids );
    } else {
        ( $word_matrix, $word_list ) = MediaWords::DBI::Stories::WordMatrix::get_story_word_matrix( $db, $stories_ids );
    }

    $self->status_ok( $c, entity => { word_matrix => $word_matrix, word_list => $word_list } );

}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
