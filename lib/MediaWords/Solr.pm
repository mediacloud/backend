package MediaWords::Solr;

use strict;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME MediaWords::Solr - functions for querying solr

=head1 SYNOPSIS

    my $results = MediaWords::Solr::query( $db, { q => 'obama' } );

    my $sentences = $results->{ response }->{ docs };
    map { print "found sentence: $_->{ sentence }\n" } @{ $sentencs };

=head1 DESCRIPTION

Functions for querying the solr server.  More information about solr integration at docs/solr.markdown.

=cut

use JSON;
use List::Util;
use Time::HiRes qw(gettimeofday tv_interval);

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Languages::Language;
use MediaWords::Solr::PseudoQueries;
use MediaWords::Util::Config;
use MediaWords::Util::Text;
use MediaWords::Util::Web;
use List::MoreUtils qw ( uniq );
use HTTP::Request::Common qw( POST );

use Time::HiRes;

# numFound from last query() call, accessible get get_last_num_found
my $_last_num_found;

# mean number of sentences per story from the last search_stories() call
my $_last_sentences_per_story;

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
    -

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

=head2 get_last_sentences_per_story

Get the ratio of sentences per story for the last search_stories call.  This function can be useful for generating very
vague guesses of the number of stories matching query without having to do the slow solr query to get the exact count.
This function does not perform a solr query but instead just references a stored variable.

=cut

sub get_last_sentences_per_story
{
    return $_last_sentences_per_story;
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

    print STDERR ( $_last_num_found ? $_last_num_found : 'undef' ) . " matches found.\n" if ( $ENV{ MC_SOLR_TRACE } );

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

=head2 query_encoded_json( $db, $params, $c )

Execute a query on the solr server using the given params.  Return a maximum of 1 million sentences.

The $params argument is a hash of the cgi args to solr, detailed here:
https://wiki.apache.org/solr/CommonQueryParameters.

The $c argument is optional and is used to pass the solr response back up to catalyst in the case of an error.

The query ($params->{ q }) is transformed into two ways -- lower case boolean operators are uppercased to make
solr recognize them as boolean queries and psuedo queries (see the api docs at mediacloud.org/api and PseudoQueries.pm)
are translated into solr clauses.

Return the raw encoded json from solr in the format described here:

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
    $params->{ df }   //= 'sentence';

    $params->{ rows } = List::Util::min( $params->{ rows }, 1000000 );

    _uppercase_boolean_operators( $params->{ q } );
    _uppercase_boolean_operators( $params->{ fq } );

    $params->{ q }  = MediaWords::Solr::PseudoQueries::transform_query( $params->{ q } );
    $params->{ fq } = MediaWords::Solr::PseudoQueries::transform_query( $params->{ fq } );

    # Ensure that only UTF-8 strings get passed to Solr
    my $encoded_params = MediaWords::Util::Text::recursively_encode_to_utf8( $params );

    my $url_action = $params->{ 'clustering.engine' } ? 'clustering' : 'select';

    my $url = sprintf( '%s/%s/%s', get_solr_url(), get_live_collection( $db ), $url_action );

    my $ua = MediaWords::Util::Web::UserAgent;

    $ua->timeout( 300 );
    $ua->max_size( undef );

    if ( $ENV{ MC_SOLR_TRACE } )
    {
        say STDERR "Executing Solr query on $url ...";
        say STDERR 'Encoded parameters: ' . Dumper( $encoded_params );
    }

    my $t0 = [ gettimeofday ];

    my $request = POST( $url, $encoded_params );
    $request->content_type( 'application/x-www-form-urlencoded; charset=utf-8' );

    my $res = $ua->request( $request );

    if ( $ENV{ MC_SOLR_TRACE } )
    {
        say STDERR "query returned in " . tv_interval( $t0, [ gettimeofday ] ) . "s.";
    }

    unless ( $res->is_success )
    {
        my $error_message;

        if ( MediaWords::Util::Web::response_error_is_client_side( $res ) )
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

                    eval { $solr_response_json = decode_json( $solr_response_maybe_json ) };
                    unless ( $@ )
                    {
                        if (    exists( $solr_response_json->{ error }->{ msg } )
                            and exists( $solr_response_json->{ responseHeader }->{ params } ) )
                        {
                            my $solr_error_msg = $solr_response_json->{ error }->{ msg };
                            my $solr_params    = encode_json( $solr_response_json->{ responseHeader }->{ params } );

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

    return $res->content;
}

=head2 query( $db, $params, $c )

Same as query_encoded_json but returns a perl hash of the decoded json.

=cut

sub query($$;$)
{
    my ( $db, $params, $c ) = @_;

    my $json = query_encoded_json( $db, $params, $c );

    my $data;
    eval { $data = decode_json( $json ) };
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
        return [ $1 ];
    }

    if ( $q =~ /^stories_id:\([\s\d]+\)$/ )
    {
        my $stories_ids;
        while ( $q =~ /(\d+)/g )
        {
            push( @{ $stories_ids }, $1 );
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

    $p->{ fl }            = 'stories_id';
    $p->{ group }         = 'true';
    $p->{ 'group.field' } = 'stories_id';

    my $response = query( $db, $p );

    my $groups = $response->{ grouped }->{ stories_id }->{ groups };
    my $stories_ids = [ map { $_->{ doclist }->{ docs }->[ 0 ]->{ stories_id } } @{ $groups } ];

    my $sentence_counts = [ map { $_->{ doclist }->{ numFound } } @{ $groups } ];

    if ( @{ $sentence_counts } > 0 )
    {
        $_last_sentences_per_story = List::Util::sum( @{ $sentence_counts } ) / scalar( @{ $sentence_counts } );
    }
    else
    {
        $_last_sentences_per_story = 0;
    }

    print STDERR "last_sentences_per_story: $_last_sentences_per_story\n" if ( $ENV{ MC_SOLR_TRACE } );

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

    MediaWords::DBI::Stories::attach_story_meta_data_to_stories( $db, $stories );

    $stories = [ grep { $_->{ url } } @{ $stories } ];

    return $stories;
}

=head2 search_for_processed_stories_ids( $db, $q, $fq, $last_ps_id, $num_stories, $sort )

Return the first $num_stories processed_stories_id that match the given query, sorted by processed_stories_id and with
processed_stories_id greater than $last_ps_id.   Returns at most $num_stories stories.  If $sort is specified as
'bitly_click_count', tell solr to sort by 'bitly_click_count desc'.

=cut

sub search_for_processed_stories_ids($$$$$;$)
{
    my ( $db, $q, $fq, $last_ps_id, $num_stories, $sort ) = @_;

    return [] unless ( $num_stories );

    my $params;

    $params->{ q }             = $q;
    $params->{ fq }            = $fq;
    $params->{ fl }            = 'processed_stories_id';
    $params->{ rows }          = $num_stories;
    $params->{ group }         = 'true';
    $params->{ 'group.field' } = 'stories_id';

    $params->{ sort } = 'processed_stories_id asc';
    if ( $sort and $sort eq 'bitly_click_count' )
    {
        $params->{ sort } = 'bitly_click_count desc';
    }

    if ( $last_ps_id )
    {
        my $min_ps_id = $last_ps_id + 1;
        $params->{ fq } = [ @{ $params->{ fq } }, "processed_stories_id:[$min_ps_id TO *]" ];
    }

    my $response = query( $db, $params );

    my $groups = $response->{ grouped }->{ stories_id }->{ groups };
    my $ps_ids = [ map { $_->{ doclist }->{ docs }->[ 0 ]->{ processed_stories_id } } @{ $groups } ];

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

Return all of the media ids that match the solr query by sampling solr results.

Performs the query on solr and returns up to 200,000 randomly sorted sentences, then culls the list of media_ids from
the list of sampled sentences.

=cut

sub search_for_media_ids ($$)
{
    my ( $db, $params ) = @_;

    my $p = { %{ $params } };

    $p->{ fl }            = 'media_id';
    $p->{ group }         = 'true';
    $p->{ 'group.field' } = 'media_id';
    $p->{ sort }          = 'random_1 asc';
    $p->{ rows }          = 200_000;

    my $response = query( $db, $p );

    my $groups = $response->{ grouped }->{ media_id }->{ groups };
    my $media_ids = [ map { $_->{ groupValue } } @{ $groups } ];

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

=head2 query_clustered_stories ( $db, $params )

Run a solr query and return a list of stories arranger into clusters by solr

=cut

sub query_clustered_stories($$;$)
{
    my ( $db, $params, $c ) = @_;

    # restrict to titles only
    $params->{ q } = $params->{ q } ? "( $params->{ q } ) and story_sentences_id:0" : "story_sentences_id:0";
    $params->{ df } = 'title';

    $params->{ rows } ||= 1000;

    $params->{ sort } ||= 'bitly_click_count desc';

    # lingo clustering configuration - generated using carrot2-workbench; generally these are asking the engine
    # to give us fewer, bigger clusters
    my $min_cluster_size = int( log( $params->{ rows } ) / log( 2 ) ) + 1;

    $params->{ 'clustering.engine' }                                = 'lingo';
    $params->{ 'DocumentAssigner.minClusterSize' }                  = $min_cluster_size;
    $params->{ 'LingoClusteringAlgorithm.clusterMergingThreshold' } = 0.5;
    $params->{ 'LingoClusteringAlgorithm.desiredClusterCountBase' } = 10;

    my $response = query( $db, $params, $c );

    for my $cluster ( @{ $response->{ clusters } } )
    {
        $cluster->{ stories_ids } = [ map { $_ =~ s/\!.*//; $_ } @{ $cluster->{ docs } } ];
    }

    my $all_stories_ids = [];
    map { push( @{ $all_stories_ids }, @{ $_->{ stories_ids } } ) } @{ $response->{ clusters } };

    my $ids_table   = $db->get_temporary_ids_table( $all_stories_ids );
    my $all_stories = $db->query( <<SQL )->hashes;
select s.stories_id, s.publish_date, s.title, s.url,
        m.media_id, m.name media_name, m.url media_url, language,
        coalesce( b.click_count, 0 ) bitly_clicks
    from stories s
        join media m on ( s.media_id = m.media_id )
        left join bitly_clicks_total b on ( s.stories_id = b.stories_id )
    where s.stories_id in ( select id from $ids_table )
SQL

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $all_stories };

    my $clusters = [];
    for my $cluster ( @{ $response->{ clusters } } )
    {
        my $cluster_stories = [];
        for my $stories_id ( @{ $cluster->{ stories_ids } } )
        {
            my $story = $stories_lookup->{ $stories_id } || die( "can't find story for stories_id '$stories_id'" );
            push( @{ $cluster_stories }, $story );
        }

        $cluster_stories = [ sort { $b->{ bitly_clicks } <=> $a->{ bitly_clicks } } @{ $cluster_stories } ];

        push(
            @{ $clusters },
            {
                label   => join( ' / ', @{ $cluster->{ labels } } ),
                score   => $cluster->{ score },
                stories => $cluster_stories
            }
        );
    }

    $clusters = [ sort { $b->{ score } <=> $a->{ score } } @{ $clusters } ];

    return $clusters;
}

1;
