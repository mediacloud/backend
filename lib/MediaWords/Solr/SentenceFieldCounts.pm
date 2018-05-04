package MediaWords::Solr::SentenceFieldCounts;

use strict;
use warnings;

use MediaWords::CommonLibs;
use MediaWords::Solr;

use Data::Dumper;
use List::Util qw/min/;

# perform the solr query and collect the sentence ids.  query postgres for the sentences and associated tags
# and return counts for each of the following fields:
# publish_day, media_id, language, sentence_tags_id, media_tags_id, story_tags_id
sub get_counts($;$$$$$)
{
    my ( $db, $q, $fq, $sample_size, $tag_sets_id, $include_stats ) = @_;

    if ( $fq and !ref( $fq ) )
    {
        $fq = [ $fq ];
    }

    $fq ||= [];
    $sample_size ||= 1000;
    $tag_sets_id += 0;

    $sample_size = min( $sample_size, 100_000 );

    unless ( $q or ( $fq && @{ $fq } ) )
    {
        return [];
    }

    my $solr_params = {
        q    => $q,
        fq   => $fq,
        rows => $sample_size,
        fl   => 'stories_id',
        sort => 'random_1 asc',
    };

    my $data = MediaWords::Solr::query( $db, $solr_params );

    my $sentences_found = $data->{ response }->{ numFound };
    my $ids = [ map { int( $_->{ 'stories_id' } ) } @{ $data->{ response }->{ docs } } ];

    my $tag_set_clause = $tag_sets_id ? "AND t.tag_sets_id = $tag_sets_id" : '';

    $ids = [ map { int( $_ ) } @{ $ids } ];

    my $ids_table = $db->get_temporary_ids_table( $ids );

    my $counts = $db->query(
        <<SQL
        SELECT
            COUNT(*) AS count,
            t.tags_id AS tags_id,
            t.tag,
            t.label,
            t.tag_sets_id
        FROM stories_tags_map AS stm
            JOIN tags AS t ON (
                stm.tags_id = t.tags_id
                $tag_set_clause
            )
        WHERE stm.stories_id IN (
            SELECT id
            FROM $ids_table
        )
        GROUP BY t.tags_id
        ORDER BY COUNT(*) DESC
SQL
    )->hashes;

    if ( $include_stats )
    {
        return {
            stats => {
                num_sentences_returned => scalar( @{ $ids } ),
                num_sentences_found    => $sentences_found,
                sample_size_param      => $sample_size,
            },
            counts => $counts,
        };
    }
    else
    {
        return $counts;
    }
}

1;
