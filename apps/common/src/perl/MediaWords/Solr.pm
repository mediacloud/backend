package MediaWords::Solr;

use strict;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME MediaWords::Solr - functions for querying solr

=head1 SYNOPSIS

    my $results = MediaWords::Solr::query_solr( $db, { q => 'obama' } );

    my $sentences = $results->{ response }->{ docs };
    map { say "found sentence id: $_->{ story_sentences_id }" } @{ $sentencs };

=head1 DESCRIPTION

Functions for querying the solr server.  More information about solr integration at docs/solr.markdown.

=cut

use Encode;
use List::Util;
use Time::HiRes qw(gettimeofday tv_interval);
use URI::Escape;

use MediaWords::Solr::Query;
use MediaWords::Solr::Request;
use MediaWords::Util::Config::Common;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::Text;
use MediaWords::Util::Web;

use List::MoreUtils qw/ uniq /;


# convert any and, or, or not operations in the argument to uppercase.  if the argument is a ref, call self on all
# elements of the list.
sub _uppercase_boolean_operators
{
    return unless ( $_[ 0 ] );

    if ( ref( $_[ 0 ] ) )
    {
        map { _uppercase_boolean_operators( $_ ) } @{ $_[ 0 ] };
    }
    else
    {
        $_[ 0 ] =~ s/\b(and|or|not)\b/uc($1)/ge;
    }
}

# transform any tags_id_media: or collections_id: clauses into media_id: clauses with the media_ids
# that corresponds to the given tags
sub _insert_collection_media_ids($$)
{
    my ( $db, $q ) = @_;

    # given the argument of a tags_id_media: or collections_id: clause, return the corresponding media_ids.
    sub _get_media_ids_clause($$)
    {
        my ( $db, $arg ) = @_;

        my $tags_ids = [];
        if ( $arg =~ /^\d+/ )
        {
            push( @{ $tags_ids }, $arg );
        }
        elsif ( $arg =~ /^\((.*)\)$/ )
        {
            my $list = $1;

            $list =~ s/or/ /ig;
            $list =~ s/^\s+//;
            $list =~ s/\s+$//;

            if ( $list =~ /[^\d\s]/ )
            {
                die( "only OR clauses allowed inside tags_id_media: or collections_id: clauses: '$arg'" );
            }

            push( @{ $tags_ids }, split( /\s+/, $list ) );
        }
        elsif ( $arg =~ /^\[/ )
        {
            die( 'range queries not allowed for tags_id_media or collections_id: clauses' );
        }
        else
        {
            die( "unrecognized format of tags_id_media: or collections_id: clause: '$arg'" );
        }

        my $tags_ids_list = join( ',', @{ $tags_ids } );

        my $media_ids = $db->query( <<SQL )->flat;
select media_id from media_tags_map where tags_id in ($tags_ids_list) order by media_id
SQL

        # replace empty list with an id that will always return nothing from solr
        $media_ids = [ -1 ] unless ( scalar( @{ $media_ids } ) > 0 );

        my $media_clause = "media_id:(" . join( ' ', @{ $media_ids } ) . ")";

        return $media_clause;
    }

    $q =~ s/(tags_id_media|collections_id)\:(\d+|\([^\)]*\)|\[[^\]]*\])/_get_media_ids_clause( $db, $2 )/eg;

    return $q;
}

=head2 __query_encoded_json( $db, $params )

Execute a query on the solr server using the given params.  Return a maximum of 1 million sentences.

The $params argument is a hash of the cgi args to solr, detailed here:
https://wiki.apache.org/solr/CommonQueryParameters.

The query ($params->{ q }) is transformed: lower case boolean operators are uppercased to make
solr recognize them as boolean queries.

Return the raw encoded JSON from solr in the format described here:

https://wiki.apache.org/solr/SolJSON

=cut

sub __query_encoded_json($$)
{
    my ( $db, $params ) = @_;

    unless ( $params )
    {
        die 'params must be set.';
    }
    unless ( ref $params eq ref {} )
    {
        die 'params must be a hashref.';
    }

    $params->{ wt } = 'json';
    $params->{ rows } //= 1000;
    $params->{ df }   //= 'text';

    $params->{ rows } = List::Util::min( $params->{ rows }, 10_000_000 );

    $params->{ q } //= '';

    $params->{ fq } //= [];
    $params->{ fq } = [ $params->{ fq } ] unless ( ref( $params->{ fq } ) eq ref( [] ) );

    if ( $params->{ q } =~ /\:\[/ )
    {
        die( "range queries are not allowed in the main query.  please use a filter query instead for range queries" );
    }

    #$params->{ q } = "{!complexphrase inOrder=false} $params->{ q }" if ( $params->{ q } );

    _uppercase_boolean_operators( $params->{ q } );

    _uppercase_boolean_operators( $params->{ fq } );

    $params->{ q } = _insert_collection_media_ids( $db, $params->{ q } );

    $params->{ fq } = [ map { _insert_collection_media_ids( $db, $_ ) } @{ $params->{ fq } } ];

    my $response_content = MediaWords::Solr::Request::solr_request( 'select', {}, $params, 'application/x-www-form-urlencoded; charset=utf-8' );

    return $response_content;
}

=head2 query_solr( $db, $params )

Same as __query_encoded_json but returns a perl hash of the decoded json.

=cut

sub query_solr($$)
{
    my ( $db, $params ) = @_;

    my $json = __query_encoded_json( $db, $params );

    my $data;
    eval { $data = MediaWords::Util::ParseJSON::decode_json( $json ) };
    if ( $@ )
    {
        die( "Error parsing solr json: $@\n$json" );
    }

    if ( $data->{ error } )
    {
        die( "Error received from solr: '$json'" );
    }

    return $data;
}

# given a list of array refs, each of which points to a list
# of ids, return a list of all ids that appear in all of the
# lists
sub _get_intersection_of_lists
{
    return [] unless ( @_ );

    my $first_list = shift( @_ );
    return $first_list unless ( @_ );

    my $other_lists = \@_;

    my $id_lookup = {};
    map { $id_lookup->{ $_ } = 1 } @{ $first_list };

    for my $id_list ( @{ $other_lists } )
    {
        my $new_id_lookup = {};
        for my $id ( @{ $id_list } )
        {
            if ( $id_lookup->{ $id } )
            {
                $new_id_lookup->{ $id } = 1;
            }
        }
        $id_lookup = $new_id_lookup;
    }

    my $list = [ keys( %{ $id_lookup } ) ];

    $list = [ map { int( $_ ) } @{ $list } ];

    return $list;
}

# transform the psuedoquery fields in the query and then run a simple pattern to detect
# queries that consists of one or more AND'ed stories_id:... clauses.  For those cases,
# just return the stories ids list rather than running it through solr.  return undef if
# the query does not match.
sub _get_stories_ids_from_stories_only_q
{
    my ( $q ) = @_;

    return undef unless ( $q );

    $q =~ s/^\s*\(\s*(.*)\s*\)\s*$/$1/;
    $q =~ s/^\s+//;
    $q =~ s/\s+$//;

    my $p = index( lc( $q ), 'and' );
    if ( $p > 0 )
    {
        my $a_stories_ids = _get_stories_ids_from_stories_only_q( substr( $q, 0, $p ) ) || return undef;
        my $b_stories_ids = _get_stories_ids_from_stories_only_q( substr( $q, $p + 3 ) ) || return undef;

        return undef unless ( $a_stories_ids && $b_stories_ids );

        return _get_intersection_of_lists( $a_stories_ids, $b_stories_ids );
    }

    if ( $q =~ /^stories_id:(\d+)$/ )
    {
        return [ int( $1 ) ];
    }

    if ( $q =~ /^stories_id:\([\s\d]+\)$/ )
    {
        my $stories_ids;
        while ( $q =~ /(\d+)/g )
        {
            push( @{ $stories_ids }, int( $1 ) );
        }

        return $stories_ids;
    }

    return undef;
}

# transform the psuedoquery fields in the q and fq params and then run a simple pattern to detect
# queries that consists of one or more AND'ed stories_id:... clauses in the q param and all fq params.
# return undef if either the q or any of the fq params do not match.
sub _get_stories_ids_from_stories_only_params
{
    my ( $params ) = @_;

    my $q     = $params->{ q };
    my $fqs   = $params->{ fq };
    my $start = $params->{ start };
    my $rows  = $params->{ rows };

    # return undef if there are any unrecognized params
    my $p = { %{ $params } };
    map { delete( $p->{ $_ } ) } ( qw(q fq start rows ) );
    return undef if ( values( %{ $p } ) );

    return undef unless ( $q );

    my $stories_ids_lists = [];

    if ( $fqs )
    {
        $fqs = ref( $fqs ) ? $fqs : [ $fqs ];
        for my $fq ( @{ $fqs } )
        {
            if ( my $stories_ids = _get_stories_ids_from_stories_only_q( $fq ) )
            {
                push( @{ $stories_ids_lists }, $stories_ids );
            }
            else
            {
                return undef;
            }
        }

    }

    my $r;

    # if there are stories_ids only fqs and a '*:*' q, just use the fqs
    if ( @{ $stories_ids_lists } && ( $q eq '*:*' ) )
    {
        $r = _get_intersection_of_lists( @{ $stories_ids_lists } );
    }

    # if there were no fqs and a '*:*' q, return undef
    elsif ( $q eq '*:*' )
    {
        return undef;
    }

    # otherwise, combine q and fqs
    else
    {
        my $stories_ids = _get_stories_ids_from_stories_only_q( $q );

        return undef unless ( $stories_ids );

        $r = _get_intersection_of_lists( $stories_ids, @{ $stories_ids_lists } );
    }

    splice( @{ $r }, 0, $start ) if ( defined( $start ) );
    splice( @{ $r }, $rows ) if ( defined( $rows ) );

    return $r;
}

=head2 get_solr_num_found( $db, $params )

Execute the query and return only the number of documents found.

=cut

sub get_solr_num_found ($$)
{
    my ( $db, $params ) = @_;

    $params = { %{ $params } };
    $params->{ rows } = 0;

    my $res = query_solr( $db, $params );

    return $res->{ response }->{ numFound };
}

=head2 search_solr_for_stories_ids( $db, $params )

Return a list of all of the stories_ids that match the solr query.  Using solr side grouping on the stories_id field.

=cut

sub search_solr_for_stories_ids ($$)
{
    my ( $db, $params ) = @_;

    my $p = { %{ $params } };

    if ( my $stories_ids = _get_stories_ids_from_stories_only_params( $p ) )
    {
        return $stories_ids;
    }

    $p->{ fl } = 'stories_id';

    my $response = query_solr( $db, $p );

    my $stories_ids = [ map { $_->{ stories_id } } @{ $response->{ response }->{ docs } } ];

    return $stories_ids;
}

=head2 search_solr_for_processed_stories_ids( $db, $q, $fq, $last_ps_id, $num_stories, $sort_by_random )

Return the first $num_stories processed_stories_id that match the given query, sorted by processed_stories_id and with
processed_stories_id greater than $last_ps_id.   Returns at most $num_stories stories.  If $sort_by_random is true,
tell solr to sort results by random order.

=cut

sub search_solr_for_processed_stories_ids($$$$$;$)
{
    my ( $db, $q, $fq, $last_ps_id, $num_stories, $sort_by_random ) = @_;

    return [] unless ( $num_stories );

    my $params;

    $params->{ q }    = $q;
    $params->{ fq }   = $fq;
    $params->{ fl }   = 'processed_stories_id';
    $params->{ rows } = $num_stories;

    $params->{ sort } = 'processed_stories_id asc';
    if ( $sort_by_random )
    {
        $params->{ sort } = 'random_1 asc';
    }

    if ( $last_ps_id )
    {
        my $min_ps_id = $last_ps_id + 1;
        $params->{ fq } = [ @{ $params->{ fq } }, "processed_stories_id:[$min_ps_id TO *]" ];
    }

    my $response = query_solr( $db, $params );

    my $ps_ids = [ map { $_->{ processed_stories_id } } @{ $response->{ response }->{ docs } } ];

    return $ps_ids;
}

=head2 search_solr_for_media_ids( $db, $params )

Return all of the media ids that match the solr query.

=cut

sub search_solr_for_media_ids ($$)
{
    my ( $db, $params ) = @_;

    my $p = { %{ $params } };

    $p->{ fl }               = 'media_id';
    $p->{ facet }            = 'true';
    $p->{ 'facet.limit' }    = 1_000_000;
    $p->{ 'facet.field' }    = 'media_id';
    $p->{ 'facet.mincount' } = 1;
    $p->{ rows }             = 0;

    my $response = query_solr( $db, $p );

    my $counts = $response->{ facet_counts }->{ facet_fields }->{ media_id };

    my $media_ids = [];
    for ( my $i = 0 ; $i < scalar( @{ $counts } ) ; $i += 2 )
    {
        TRACE( $i );
        push( @{ $media_ids }, $counts->[ $i ] );
    }

    return $media_ids;
}

1;
