package MediaWords::Solr;

use strict;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME MediaWords::Solr - functions for querying solr

=head1 SYNOPSIS

    my $results = MediaWords::Solr::query( $db, { q => 'obama' } );

    my $sentences = $results->{ response }->{ docs };
    map { say "found sentence id: $_->{ story_sentences_id }" } @{ $sentencs };

=head1 DESCRIPTION

Functions for querying the solr server.  More information about solr integration at docs/solr.markdown.

=cut

use Encode;
use List::Util;
use Time::HiRes qw(gettimeofday tv_interval);
use URI::Escape;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Languages::Language;
use MediaWords::Solr::PseudoQueries;
use MediaWords::Solr::Query;
use MediaWords::Util::Config;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::Text;
use MediaWords::Util::Web;

use List::MoreUtils qw ( uniq );

use Time::HiRes;

Readonly my $QUERY_HTTP_TIMEOUT => 900;

# numFound from last query() call, accessible get get_last_num_found
my $_last_num_found;

=head1 FUNCTIONS

=head2 get_solr_url

Get a solr url from the config, returning either the single url if there is one or a random member of the list if there
is a list.

=cut

sub get_solr_url
{
    my $urls = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_url };

    my $i = int( Time::HiRes::time * 10000 ) % scalar( @{ $urls } );

    my $url = ref( $urls ) ? $urls->[ $i ] : $urls;

    $url =~ s~/+$~~;

    return $url;
}

=head2 get_live_collection( $db )

Get the name of the currently live collection, as stored in database_variables in postgres.

We configure solr to  run 2 collections (collection1 and collection2) so that we can use one for staging a full import
while the other stays live.  If you need to create a solr url using get_solr_url(), you should always use this function
to create the collection name to query the production server (or get_staging_collection() to query the staging server).

The flag for which collection is live is stored in postgres rather than in mediawords.yml so that the staging server
can be changed without needing to reboot all running clients that might query solr.

=cut

sub get_live_collection
{
    my ( $db ) = @_;

    my ( $collection ) = $db->query( "select value from database_variables where name = 'live_solr_collection' " )->flat;

    return $collection || 'collection1';
}

=head2 get_staging_collection( $db )

Get the name of the staging collection.  See get_live_collection() above.

=cut

sub get_staging_collection
{
    my ( $db ) = @_;

    my $live_collection = get_live_collection( $db );

    return $live_collection eq 'collection1' ? 'collection2' : 'collection1';
}

=head2 swap_live_collection( $db )

Swap which collection is live and which is staging.  See get_live_collection() above.

=cut

sub swap_live_collection
{
    my ( $db ) = @_;

    my $current_staging_collection = get_staging_collection( $db );

    $db->begin;

    $db->query( "delete from database_variables where name = 'live_solr_collection'" );
    $db->create( 'database_variables', { name => 'live_solr_collection', value => $current_staging_collection } );

    $db->commit;
}

=head2 get_last_num_found

Get the number of sentences found from the last solr query run in this process.  This function does not perform a solr
query but instead just references a stored variable.

=cut

sub get_last_num_found
{
    return $_last_num_found;
}

# set _last_num_found for get_last_num_found
sub _set_last_num_found
{
    my ( $res ) = @_;

    if ( defined( $res->{ response }->{ numFound } ) )
    {
        $_last_num_found = $res->{ response }->{ numFound };
    }
    elsif ( $res->{ grouped } )
    {
        my $group_key = ( keys( %{ $res->{ grouped } } ) )[ 0 ];

        $_last_num_found = $res->{ grouped }->{ $group_key }->{ matches };
    }
    else
    {
        $_last_num_found = undef;
    }

    TRACE( ( $_last_num_found ? $_last_num_found : 0 ) . " matches found." );

}

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

        #my $media_clause = consolidate_id_query( 'media_id', $media_ids );
        my $media_clause = "media_id:(" . join( ' ', @{ $media_ids } ) . ")";

        return $media_clause;
    }

    $q =~ s/(tags_id_media|collections_id)\:(\d+|\([^\)]*\)|\[[^\]]*\])/_get_media_ids_clause( $db, $2 )/eg;

    return $q;
}

=head2 query_encoded_json( $db, $params, $c )

Execute a query on the solr server using the given params.  Return a maximum of 1 million sentences.

The $params argument is a hash of the cgi args to solr, detailed here:
https://wiki.apache.org/solr/CommonQueryParameters.

The $c argument is optional and is used to pass the solr response back up to catalyst in the case of an error.

The query ($params->{ q }) is transformed into two ways -- lower case boolean operators are uppercased to make
solr recognize them as boolean queries and psuedo queries (see the api docs at mediacloud.org/api and PseudoQueries.pm)
are translated into solr clauses.

Return the raw encoded JSON from solr in the format described here:

https://wiki.apache.org/solr/SolJSON

=cut

sub query_encoded_json($$;$)
{
    my ( $db, $params, $c ) = @_;

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

    $params->{ q } = MediaWords::Solr::PseudoQueries::transform_query( $params->{ q } );
    $params->{ q } = _insert_collection_media_ids( $db, $params->{ q } );

    $params->{ fq } = [ map { _insert_collection_media_ids( $db, $_ ) } @{ $params->{ fq } } ];

    my $url = sprintf( '%s/%s/select', get_solr_url(), get_live_collection( $db ) );

    my $ua = MediaWords::Util::Web::UserAgent->new();

    $ua->set_timeout( $QUERY_HTTP_TIMEOUT );
    $ua->set_max_size( undef );

    # Remediate CVE-2017-12629
    if ( $params->{ q } )
    {
        if ( $params->{ q } =~ /xmlparser/i )
        {
            LOGCONFESS "XML queries are not supported.";
        }
    }

    # make sure we're not sending fq=[] in the cgi post data
    delete( $params->{ fq } ) unless ( @{ $params->{ fq } } );

    TRACE "Executing Solr query on $url ...";
    TRACE 'Parameters: ' . Dumper( $params );
    my $t0 = [ gettimeofday ];

    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
    $request->set_content_type( 'application/x-www-form-urlencoded; charset=utf-8' );

    $request->set_content_utf8( $params );

    my $res = $ua->request( $request );

    TRACE "query returned in " . tv_interval( $t0, [ gettimeofday ] ) . "s.";

    unless ( $res->is_success )
    {
        my $error_message;

        if ( $res->error_is_client_side() )
        {

            # LWP error (LWP wasn't able to connect to the server or something like that)
            $error_message = 'LWP error: ' . $res->decoded_content;

        }
        else
        {

            my $status_code = $res->code;
            if ( $status_code =~ /^4\d\d$/ )
            {
                # Client error - set default message
                $error_message = 'Client error: ' . $res->status_line . ' ' . $res->decoded_content;

                # Parse out Solr error message if there is one
                my $solr_response_maybe_json = $res->decoded_content;
                if ( $solr_response_maybe_json )
                {
                    my $solr_response_json;

                    eval { $solr_response_json = MediaWords::Util::ParseJSON::decode_json( $solr_response_maybe_json ) };
                    unless ( $@ )
                    {
                        if (    exists( $solr_response_json->{ error }->{ msg } )
                            and exists( $solr_response_json->{ responseHeader }->{ params } ) )
                        {
                            my $solr_error_msg = $solr_response_json->{ error }->{ msg };
                            my $solr_params =
                              MediaWords::Util::ParseJSON::encode_json(
                                $solr_response_json->{ responseHeader }->{ params } );

                            # If we were able to decode Solr error message, overwrite the default error message with it
                            $error_message = 'Solr error: "' . $solr_error_msg . '", params: ' . $solr_params;
                        }
                    }
                }

            }
            elsif ( $status_code =~ /^5\d\d/ )
            {
                # Server error or some other error
                $error_message = 'Server / other error: ' . $res->status_line . ' ' . $res->decoded_content;
            }

        }

        if ( $c )
        {
            # Set HTTP status code if Catalyst object is present
            $c->response->status( $res->code );
        }
        die "Error fetching Solr response: $error_message";
    }

    return $res->decoded_content;
}

=head2 query( $db, $params, $c )

Same as query_encoded_json but returns a perl hash of the decoded json.

=cut

sub query($$;$)
{
    my ( $db, $params, $c ) = @_;

    my $json = query_encoded_json( $db, $params, $c );

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

    _set_last_num_found( $data );

    return $data;
}

# order the list of sentences by the given list of stories_ids
sub _order_sentences_by_stories_ids($$)
{
    my ( $stories_ids, $story_sentences ) = @_;

    my $ss = {};
    map { push( @{ $ss->{ $_->{ stories_id } } }, $_ ) } @{ $story_sentences };

    my $ordered_sentences = [];
    map { push( @{ $ordered_sentences }, @{ $ss->{ $_ } } ) if ( $ss->{ $_ } ) } @{ $stories_ids };

    return $ordered_sentences;
}

=head2 quey_matching_sentences( $db, $solr_params)

Query for solr for stories matching the given query, then return all sentences within those stories that match
the the inclusive regex translation of the solr query.  The inclusive regex is the regex generated by translating
the solr boolean query into a flat list of ORs, so  [ ( foo and bar ) or baz ] would get translated first into
[ foo or bar or baz ] and then into a regex.

Order the sentences in the same order as the list of stories_ids returned by solr unless $random_limit is specified.
If $random_limit is specified, return at most $random_limit stories, randomly sorted.

=cut

sub query_matching_sentences($$;$)
{
    my ( $db, $params, $random_limit ) = @_;

    my $stories_ids = search_for_stories_ids( $db, $params );

    return [] unless ( @{ $stories_ids } );

    die( "too many stories (limit is 1,000,000)" ) if ( scalar( @{ $stories_ids } ) > 1_000_000 );

    my $stories_ids_list = join( ',', @{ $stories_ids } );

    my $re_clause = 'true';

    my $re = eval { '(?isx)' . MediaWords::Solr::Query::parse( $params->{ q } )->inclusive_re() };
    if ( $@ )
    {
        if ( $@ !~ /McSolrEmptyQueryException/ )
        {
            die( "Error translating solr query to regex: $@" );
        }
    }
    else
    {
        $re_clause = "sentence ~ " . $db->quote( $re );
    }

    my $order_limit = $random_limit ? "order by random() limit $random_limit" : 'order by sentence_number';

    my $ids_table = $db->get_temporary_ids_table( $stories_ids );

    my $story_sentences = $db->query( <<SQL )->hashes;
select
        ss.sentence,
        ss.media_id,
        ss.publish_date,
        ss.sentence_number,
        ss.stories_id,
        ss.story_sentences_id,
        ss.language,
        s.language story_language
    from
        story_sentences ss
        join stories s using ( stories_id )
        join $ids_table ids on ( s.stories_id = ids.id )
    where
        $re_clause 
   $order_limit 
SQL

    return $random_limit ? $story_sentences : _order_sentences_by_stories_ids( $stories_ids, $story_sentences );
}

# given a list of array refs, each of which points to a list
# of ids, return a list of all ids that appear in all of the
# lists
sub _get_intersection_of_id_array_refs
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

        return _get_intersection_of_id_array_refs( $a_stories_ids, $b_stories_ids );
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

    $params->{ q }  = MediaWords::Solr::PseudoQueries::transform_query( $params->{ q } );
    $params->{ fq } = MediaWords::Solr::PseudoQueries::transform_query( $params->{ fq } );

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
        $r = _get_intersection_of_id_array_refs( @{ $stories_ids_lists } );
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

        $r = _get_intersection_of_id_array_refs( $stories_ids, @{ $stories_ids_lists } );
    }

    splice( @{ $r }, 0, $start ) if ( defined( $start ) );
    splice( @{ $r }, $rows ) if ( defined( $rows ) );

    return $r;
}

=head2 search_for_stories_ids( $db, $params )

Return a list of all of the stories_ids that match the solr query.  Using solr side grouping on the stories_id field.

=cut

sub search_for_stories_ids ($$)
{
    my ( $db, $params ) = @_;

    my $p = { %{ $params } };

    if ( my $stories_ids = _get_stories_ids_from_stories_only_params( $p ) )
    {
        return $stories_ids;
    }

    $p->{ fl } = 'stories_id';

    my $response = query( $db, $p );

    my $stories_ids = [ map { $_->{ stories_id } } @{ $response->{ response }->{ docs } } ];

    return $stories_ids;
}

=head2 search_for_stories( $db, $params )

Call search_for_stories_ids() above and then query postgres for the stories returned by solr.  Include stories.* and
media_name as the returned fields.

=cut

sub search_for_stories ($$)
{
    my ( $db, $params ) = @_;

    my $stories_ids = search_for_stories_ids( $db, $params );

    my $stories = [ map { { stories_id => $_ } } @{ $stories_ids } ];

    $stories = MediaWords::DBI::Stories::attach_story_meta_data_to_stories( $db, $stories );

    $stories = [ grep { $_->{ url } } @{ $stories } ];

    return $stories;
}

=head2 search_for_processed_stories_ids( $db, $q, $fq, $last_ps_id, $num_stories, $sort )

Return the first $num_stories processed_stories_id that match the given query, sorted by processed_stories_id and with
processed_stories_id greater than $last_ps_id.   Returns at most $num_stories stories.  If $sort is specified as
'random', tell solr to sort results by random order.

=cut

sub search_for_processed_stories_ids($$$$$;$)
{
    my ( $db, $q, $fq, $last_ps_id, $num_stories, $sort ) = @_;

    return [] unless ( $num_stories );

    my $params;

    $params->{ q }    = $q;
    $params->{ fq }   = $fq;
    $params->{ fl }   = 'processed_stories_id';
    $params->{ rows } = $num_stories;

    $params->{ sort } = 'processed_stories_id asc';
    if ( $sort and $sort eq 'random' )
    {
        $params->{ sort } = 'random_1 asc';
    }

    if ( $last_ps_id )
    {
        my $min_ps_id = $last_ps_id + 1;
        $params->{ fq } = [ @{ $params->{ fq } }, "processed_stories_id:[$min_ps_id TO *]" ];
    }

    my $response = query( $db, $params );

    my $ps_ids = [ map { $_->{ processed_stories_id } } @{ $response->{ response }->{ docs } } ];

    return $ps_ids;
}

=head2 get_num_found( $db, $params )

Execute the query and return only the number of documents found.

=cut

sub get_num_found ($$)
{
    my ( $db, $params ) = @_;

    $params = { %{ $params } };
    $params->{ rows } = 0;

    my $res = query( $db, $params );

    return $res->{ response }->{ numFound };
}

=head2 search_for_media_ids( $db, $params )

Return all of the media ids that match the solr query.

=cut

sub search_for_media_ids ($$)
{
    my ( $db, $params ) = @_;

    my $p = { %{ $params } };

    $p->{ fl }               = 'media_id';
    $p->{ facet }            = 'true';
    $p->{ 'facet.limit' }    = 1_000_000;
    $p->{ 'facet.field' }    = 'media_id';
    $p->{ 'facet.mincount' } = 1;
    $p->{ rows }             = 0;

    my $response = query( $db, $p );

    my $counts = $response->{ facet_counts }->{ facet_fields }->{ media_id };

    my $media_ids = [];
    for ( my $i = 0 ; $i < scalar( @{ $counts } ) ; $i += 2 )
    {
        TRACE( $i );
        push( @{ $media_ids }, $counts->[ $i ] );
    }

    return $media_ids;
}

=head2 search_for_media( $db, $params )

Query postgres for media.* for all media matching the ids returned by search_for_media_ids().

=cut

sub search_for_media ($$)
{
    my ( $db, $params ) = @_;

    my $media_ids = search_for_media_ids( $db, $params );

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( $media_ids );

    my $media = $db->query( "select * from media where media_id in ( select id from $ids_table ) " )->hashes;

    $db->commit;

    return $media;
}

# given a list of $ids for $field, consolidate them into ranges where possible.
# so transform this:
#     stories_id:( 1 2 4 5 6 7 9 )
# into:
#    stories_id:( 1 2 9 ) stories_id:[ 4 TO 7 ]
sub consolidate_id_query
{
    my ( $field, $ids ) = @_;

    die( "ids list" ) unless ( @{ $ids } );

    $ids = [ sort { $a <=> $b } @{ $ids } ];

    my $singletons = [ -10 ];
    my $ranges = [ [ -10 ] ];
    for my $id ( @{ $ids } )
    {
        if ( $id == ( $ranges->[ -1 ]->[ -1 ] + 1 ) )
        {
            push( @{ $ranges->[ -1 ] }, $id );
        }
        elsif ( $id == ( $singletons->[ -1 ] + 1 ) )
        {
            push( @{ $ranges }, [ pop( @{ $singletons } ), $id ] );
        }
        else
        {
            push( @{ $singletons }, $id );
        }
    }

    shift( @{ $singletons } );
    shift( @{ $ranges } );

    my $long_ranges = [];
    for my $range ( @{ $ranges } )
    {
        if ( scalar( @{ $range } ) > 2 )
        {
            push( @{ $long_ranges }, $range );
        }
        else
        {
            push( @{ $singletons }, @{ $range } );
        }
    }

    my $queries = [];

    push( @{ $queries }, map { "$field:[$_->[ 0 ] TO $_->[ -1 ]]" } @{ $long_ranges } );
    push( @{ $queries }, "$field:(" . join( ' ', @{ $singletons } ) . ')' ) if ( scalar( @{ $singletons } ) > 0 );

    my $query = join( ' ', @{ $queries } );

    return $query;
}

1;
