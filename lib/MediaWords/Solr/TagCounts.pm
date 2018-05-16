package MediaWords::Solr::TagCounts;

use strict;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME MediaWords::Solr::TagCounts

=head1 SYNOPSIS

    my $tag_counts = MediaWords::Solr::TagCounts::query_tag_counts( $db, { q => 'obama' } );

    for my $tag_count ( @{ $tag_counts } )
    {
        print( "$tag_count->{ label }: $tag_count->{ count }\n" );
    }

=head1 DESCRIPTION

Functions for counting tags associated with stories that match a solr query.

=cut

use MediaWords::Solr;

Readonly my $DEFAULT_LIMIT => 100;

=head1 FUNCTIONS

=head2 query_tag_counts( $db, $args )

Run a query on solr and return a count of tags associate with tags matching the query.

The $args parameter should be a hash with some of the following fields:

* q - query to run on solr (required)
* limit - limit to this number of the most common tags (default = 100)
* tag_sets_id - only return tags belonging to the given tag set (default = none)

Note that the limit argument is applied before the tag_sets_id, so the number of tags returned will likely
be less than the limit argument.

Returns the list of tag hashes, with the 'count' field inserted into each tag hash.

=cut

sub query_tag_counts($$)
{
    my ( $db, $args ) = @_;

    my $q           = $args->{ q }           || die( "must specifify 'q' in \$args" );
    my $fq          = $args->{ fq }          || '';
    my $limit       = $args->{ limit }       || $DEFAULT_LIMIT;
    my $tag_sets_id = $args->{ tag_sets_id } || 0;

    $tag_sets_id = int( $tag_sets_id );

    my $solr_params = {};
    $solr_params->{ q }                = $q;
    $solr_params->{ fq }               = $fq;
    $solr_params->{ rows }             = 0;
    $solr_params->{ facet }            = 'true';
    $solr_params->{ 'facet.field' }    = 'tags_id_stories';
    $solr_params->{ 'facet.mincount' } = 1;
    $solr_params->{ 'facet.limit' }    = int( $limit );

    my $response = MediaWords::Solr::query( $db, $solr_params );

    my $tags_id_counts_list = $response->{ facet_counts }->{ facet_fields }->{ tags_id_stories };

    my $tags_id_counts = {};
    for ( my $i = 0 ; $i < @{ $tags_id_counts_list } ; $i += 2 )
    {
        $tags_id_counts->{ $tags_id_counts_list->[ $i ] } = $tags_id_counts_list->[ $i + 1 ];
    }

    my $tags_ids_list = join( ',', keys( %{ $tags_id_counts } ) );

    my $tag_set_clause = '1=1';
    if ( $tag_sets_id )
    {
        $tag_set_clause = "tag_sets_id = $tag_sets_id";
    }

    INFO( Dumper( $db->query( <<SQL )->flat ) );
explain select t.*, ts.name tag_set_name, ts.label tag_set_label
    from tags t
        join tag_sets ts using ( tag_sets_id )
    where
        t.tags_id in ( $tags_ids_list ) and
        $tag_set_clause
SQL

    my $tags = $db->query( <<SQL )->hashes;
select t.*, ts.name tag_set_name, ts.label tag_set_label
    from tags t
        join tag_sets ts using ( tag_sets_id )
    where
        t.tags_id in ( $tags_ids_list ) and
        $tag_set_clause
SQL

    my $tag_counts = [];
    for my $tag ( @{ $tags } )
    {
        $tag->{ count } = $tags_id_counts->{ $tag->{ tags_id } };
        push( @{ $tag_counts }, $tag );
    }

    $tag_counts = [ sort { $b->{ count } <=> $a->{ count } } @{ $tag_counts } ];
}

1;

