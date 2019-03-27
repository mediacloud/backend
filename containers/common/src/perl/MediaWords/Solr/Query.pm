package MediaWords::Solr::Query;

=head1 NAME MediaWords::Solr::Query - functions for parsing solr queries

=head1 SYNOPSIS

my $tsquery = MediaWords::Solr::Query::convert_to_tsquery( "foo and bar" )

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use Time::Piece;

import_python_module( __PACKAGE__, 'mediawords.solr.query' );


# for the given topic, get a solr publish_date clause that will return one month of the seed query,
# starting at start_date and offset by $month_offset months.  return undef if $month_offset puts
# the start date past the topic start date.
sub __get_solr_query_month_clause($$)
{
    my ( $topic, $month_offset ) = @_;

    my $topic_start = Time::Piece->strptime( $topic->{ start_date }, "%Y-%m-%d" );
    my $topic_end   = Time::Piece->strptime( $topic->{ end_date },   "%Y-%m-%d" );

    my $offset_start = $topic_start->add_months( $month_offset );
    my $offset_end   = $offset_start->add_months( 1 );

    return undef if ( $offset_start > $topic_end );

    $offset_end = $topic_end if ( $offset_end > $topic_end );

    my $solr_start = $offset_start->strftime( '%Y-%m-%d' ) . 'T00:00:00Z';
    my $solr_end   = $offset_end->strftime( '%Y-%m-%d' ) . 'T23:59:59Z';

    my $date_clause = "publish_day:[$solr_start TO $solr_end]";

    return $date_clause;
}

# get the full solr query by combining the solr_seed_query with generated clauses for start and
# end date from topics and media clauses from topics_media_map and topics_media_tags_map.
# only return a query for up to a month of the given a query, using the zero indexed $month_offset to
# fetch $month_offset to return months after the first.  return undef if the month_offset puts the
# query start date beyond the topic end date. otherwise return hash in the form of { q => query, fq => filter_query }
sub get_full_solr_query_for_topic($$;$$$$)
{
    my ( $db, $topic, $media_ids, $media_tags_ids, $month_offset ) = @_;

    $month_offset ||= 0;

    my $date_clause = __get_solr_query_month_clause( $topic, $month_offset );

    return undef unless ( $date_clause );

    my $solr_query = "( $topic->{ solr_seed_query } )";

    my $media_clauses = [];
    my $topics_id     = $topic->{ topics_id };

    $media_ids ||= $db->query( "select media_id from topics_media_map where topics_id = ?", $topics_id )->flat;
    if ( @{ $media_ids } )
    {
        my $media_ids_list = join( ' ', @{ $media_ids } );
        push( @{ $media_clauses }, "media_id:( $media_ids_list )" );
    }

    $media_tags_ids ||= $db->query( "select tags_id from topics_media_tags_map where topics_id = ?", $topics_id )->flat;
    if ( @{ $media_tags_ids } )
    {
        my $media_tags_ids_list = join( ' ', @{ $media_tags_ids } );
        push( @{ $media_clauses }, "tags_id_media:( $media_tags_ids_list )" );
    }

    if ( !( $topic->{ solr_seed_query } =~ /media_id\:|tags_id_media\:/ ) && !@{ $media_clauses } )
    {
        die( "query must include at least one media source or media set" );
    }

    if ( @{ $media_clauses } )
    {
        my $media_clause_list = join( ' or ', @{ $media_clauses } );
        $solr_query .= " and ( $media_clause_list )";
    }

    my $solr_params = { q => $solr_query, fq => $date_clause };

    DEBUG( "full solr query: q = $solr_query, fq = $date_clause" );

    return $solr_params;
}

1;
