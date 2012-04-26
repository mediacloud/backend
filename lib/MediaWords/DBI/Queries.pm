package MediaWords::DBI::Queries;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# various routines for accessing the queries table and for querying
# the aggregate vector tables (daily/weekly/top_500_weekly)_words

use strict;

use Data::Dumper;
use JSON;

#use Data::Compare;

use MediaWords::Util::BigPDLVector qw(vector_new vector_set vector_cos_sim);
use MediaWords::Util::SQL;
use MediaWords::StoryVectors;

use Readonly;

# max number of sentences to return in various get_*_stories_with_sentences functions
use constant MAX_QUERY_SENTENCES => 1000;

# get a text description for the query based on the media sets, dashboard topics, and dates.
# this is internal b/c it is set by find_query_by_id and so accessible as $query->{ description }
sub _get_description
{
    my ( $query ) = @_;

    my $description;

    my $media_sets       = $query->{ media_sets };
    my $dashboard_topics = $query->{ dashboard_topics };
    my $start_date       = substr( $query->{ start_date }, 0, 12 );
    my $end_date         = substr( $query->{ end_date }, 0, 12 ) if ( $query->{ end_date } );

    if ( @{ $media_sets } > 2 )
    {
        $description =
          "in one of " . @{ $media_sets } . " media sources including " .
          join( " and ", map { $_->{ name } } @{ $media_sets }[ 0 .. 1 ] );
    }
    else
    {
        $description = "in " . join( " or ", map { $_->{ name } } @{ $media_sets } );
    }

    if ( @{ $dashboard_topics } > 2 )
    {
        $description .=
          " mentioning one of " . @{ $dashboard_topics } . " topics including " .
          join( " and ", map { $_->{ name } } @{ $dashboard_topics }[ 0 .. 1 ] );
    }
    elsif ( @{ $dashboard_topics } )
    {
        $description .= " mentioning " . join( " or ", map { $_->{ name } } @{ $dashboard_topics } );
    }

    $description .= " during the week starting $start_date";
    if ( $end_date && ( $start_date ne $end_date ) )
    {
        $description .= " through the week starting $end_date";
    }

    return $description;
}

# create a query with the given data, including creating queries_media_sets_map and
# queries_dashboard_topics_map entries for the $query->{ dashboard_topics_ids } and
# $query->{ media_sets_ids } fields.
#
# this should never be called from outside the module, because we always want to try to
# find an existing query with the given params before creating a new one.
sub _create_query
{
    my ( $db, $query_params ) = @_;

    if ( !$query_params->{ media_sets_ids } || !@{ $query_params->{ media_sets_ids } } )
    {
        die( "no media_sets_ids" );
    }

    _add_mapped_table_fields( $db, $query_params );

    $query_params->{ description } = _get_description( $query_params );
    if ( !$query_params->{ end_date } || ( $query_params->{ end_date } lt $query_params->{ start_date } ) )
    {
        $query_params->{ end_date } = $query_params->{ start_date };
    }

    $db->begin_work();

    $db->query(
        "insert into queries ( start_date, end_date, description ) " .
          "  values( date_trunc( 'week', ?::date ), date_trunc( 'week', ?::date ), ? )",
        $query_params->{ start_date },
        $query_params->{ end_date },
        $query_params->{ description }
    );

    my $queries_id = $db->last_insert_id( undef, undef, 'queries', undef );

    for my $table ( 'dashboard_topics', 'media_sets' )
    {
        for my $id ( @{ $query_params->{ $table . "_ids" } } )
        {
            $db->query( "insert into queries_${table}_map ( queries_id, ${table}_id ) values ( ?, ? ) ", $queries_id, $id );
        }
    }

    $db->commit;

    return find_query_by_id( $db, $queries_id );
}

# add dashboard_topics and media_sets fields corresponding to the existing dashboard_topics_ids
# and media_sets_ids fields in the given query
sub _add_mapped_table_fields
{
    my ( $db, $query ) = @_;

    for my $table ( 'dashboard_topics', 'media_sets' )
    {
        my $ids_field = $table . "_ids";
        if ( !ref( $query->{ $ids_field } ) )
        {
            $query->{ $ids_field } = $query->{ $ids_field } ? [ $query->{ $ids_field } ] : [];
        }

        my $ids_clause;
        if ( !@{ $query->{ $ids_field } } )
        {
            $query->{ $table } = [];
        }
        else
        {
            my $ids_list = join( ',', @{ $query->{ $ids_field } } );
            $query->{ $table } =
              [ $db->query( "select * from $table where ${table}_id in ( $ids_list ) order by ${table}_id" )->hashes ];
        }
    }
}

# find a query whose description (based on dates, media sets, and dashboard_topics)
# matches the query params
sub find_query_by_params
{
    my ( $db, $query_params ) = @_;

    _add_mapped_table_fields( $db, $query_params );

    my $description = _get_description( $query_params );

    my ( $queries_id ) = $db->query(
        "select queries_id from queries where description = ? and query_version = enum_last (null::query_version_enum ) ",
        $description )->flat;

    return find_query_by_id( $db, $queries_id );
}

# find a query that exactly matches all of the query params or
# create one if one does not already exist.
# query params should be in the form
# { start_date => $start_date, end_date => $end_date, media_sets_ids => [ $m, $m ], dashboard_sets_ids => [ $d, $d ] }.
# if no dashboard_topicss_ids are included, then return only a query that
# has no dashboard_topics_ids associated with it.
sub find_or_create_query_by_params
{
    my ( $db, $query_params ) = @_;

    return find_query_by_params( $db, $query_params ) || _create_query( $db, $query_params );
}

# set the first param to the value of the second param if the first param is not set
sub _set_alternate_param
{
    my ( $req, $p1, $p2 ) = @_;

    $req->param( $p1, $req->param( $p2 ) ) if ( !defined( $req->param( $p1 ) ) );
}

# given a request with either a media_id or a set of media_sets_ids,
# return a list of media_sets_ids.  If a media_id or medium_name is included
# return just the media set associated with that media source, otherwise
# return the media sets from the media_sets_ids param.
sub _get_media_sets_ids_from_request
{
    my ( $db, $req, $param_suffix ) = @_;

    my $ret;
    if ( my $media_id = $req->param( 'media_id' . $param_suffix ) )
    {
        my ( $media_set_id ) = $db->query( "select media_sets_id from media_sets where media_id = ?", $media_id )->flat;
        $ret = [ $media_set_id ];
    }
    elsif ( my $medium_name = $req->param( 'medium_name' . $param_suffix ) )
    {
        my $quoted_name = $db->dbh->quote( $medium_name );
        my ( $media_set_id ) = $db->query( "select media_sets_id from media_sets ms, media m " .
              "  where m.media_id = ms.media_id and m.name = $quoted_name" )->flat;
        $ret = [ $media_set_id ];
    }
    else
    {
        $ret = [ $req->param( 'media_sets_ids' . $param_suffix ) ];
    }

    $ret = [ grep { defined( $_ ) } @$ret ];
    return $ret;
}

# call find_or_create_query_by_params with params from the catalyst request object.
# if the $param_suffix param is passed, append that suffix to each of the request
# param names.  With a param_suffic of '_1',
#   ( start_date, end_date, media_id, media_sets_ids, dashboard_topics_ids )
# becomes
#   ( start_date_1, end_date_1, media_id1, media_sets_ids_1, dashboard_topics_ids_1 )
sub find_or_create_query_by_request
{
    my ( $db, $req, $param_suffix ) = @_;

    $param_suffix ||= '';

    _set_alternate_param( $req, "queries_id$param_suffix", "q$param_suffix" );

    if ( my $queries_id = $req->param( "queries_id$param_suffix" ) )
    {
        return find_query_by_id( $db, $queries_id ) || die( "Unable to find query id '$queries_id' " );
    }

    _set_alternate_param( $req, "start_date$param_suffix",           "date$param_suffix" );
    _set_alternate_param( $req, "end_date$param_suffix",             "start_date$param_suffix" );
    _set_alternate_param( $req, "media_sets_ids$param_suffix",       "media_sets_id$param_suffix" );
    _set_alternate_param( $req, "dashboard_topics_ids$param_suffix", "dashboard_topics_id$param_suffix" );

    my $media_sets_ids = _get_media_sets_ids_from_request( $db, $req, $param_suffix );
    my $start_date = $req->param( 'start_date' . $param_suffix );

    die( "No start_date or media set" ) if ( !$start_date || ( scalar( @{ $media_sets_ids } ) == 0 ) );

    my $dashboard_topics_ids = [ $req->param( 'dashboard_topics_ids' . $param_suffix ) ];
    $dashboard_topics_ids = [] if ( ( @{ $dashboard_topics_ids } == 1 ) && !$dashboard_topics_ids->[ 0 ] );

    my $query = find_or_create_query_by_params(
        $db,
        {
            start_date           => $req->param( 'start_date' . $param_suffix ),
            end_date             => $req->param( 'end_date' . $param_suffix ),
            media_sets_ids       => $media_sets_ids,
            dashboard_topics_ids => $dashboard_topics_ids
        }
    );

    return $query;
}

# return the query with the given id or undef if the id does not exist.
# attach the following fields:
# media_sets => <associated media sets>
# media_sets_ids => <associated media set ids >
# dashboards_topics => <associated dashboard topics>
# dashboard_topics_ids => <assocaited dashboard topic ids>
sub find_query_by_id
{
    my ( $db, $queries_id ) = @_;

    my $query = $db->find_by_id( 'queries', $queries_id );

    if ( !$query )
    {
        return undef;
    }

    for my $table ( 'media_sets', 'dashboard_topics' )
    {
        $query->{ $table } = [
            $db->query(
                "select distinct m.* from $table m, queries_${table}_map qm " .
                  "  where m.${table}_id = qm.${table}_id and qm.queries_id = $queries_id order by m.${table}_id"
              )->hashes
        ];
        $query->{ $table . "_names" } = [ map { $_->{ name } } @{ $query->{ $table } } ];
        $query->{ $table . "_ids" }   = [ map { $_->{ $table . "_id" } } @{ $query->{ $table } } ];
    }

    return $query;
}

# get the sql clause for the dashboard_topics_ids field.
sub get_dashboard_topics_clause
{
    my ( $query, $prefix ) = @_;

    my $dashboard_topic_clause;

    if ( $prefix )
    {
        $prefix = $prefix . '.';
    }
    else
    {
        $prefix = '';
    }

    $query->{ dashboard_topics_ids } ||= [];
    if ( !$query->{ dashboard_topics_ids } || !@{ $query->{ dashboard_topics_ids } } )
    {
        $dashboard_topic_clause = "${ prefix }" . "dashboard_topics_id is null";
    }
    else
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );
        $dashboard_topic_clause = "${ prefix }" . "dashboard_topics_id in ( $dashboard_topics_ids_list )";
    }

    return $dashboard_topic_clause;
}

sub get_dashboard_topic_names
{
    my ( $db, $query ) = @_;

    my $ret;

    say STDERR Dumper( $query );
    $query->{ dashboard_topics_ids } ||= [];

    if ( !$query->{ dashboard_topics_ids } || !@{ $query->{ dashboard_topics_ids } } )
    {
        $ret = "all";
    }
    else
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );
        my $topic_names = $db->query( "select name from dashboard_topics                                        " .
              " where dashboard_topics_id in ( $dashboard_topics_ids_list )        " )->flat;

        $ret = join ", ", @{ $topic_names };
    }

    return $ret;
}

sub get_media_set_names
{
    my ( $db, $query ) = @_;

    if ( !( $query->{ media_sets_ids } && @{ $query->{ media_sets_ids } } && $query->{ start_date } ) )
    {
        die( "media_sets_id and start_date are required" );
    }

    my $media_sets_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ media_sets_ids } );

    my $media_set_names = $db->query( "select name from media_sets where media_sets_id in ( $media_sets_ids_list ) " )->flat;

    return $media_set_names;
}

sub get_time_range
{
    my ( $db, $query ) = @_;

    if ( !( $query->{ start_date } ) )
    {
        die( "start_date is required" );
    }

    my $ret = $query->{ start_date };

    if ( defined( $query->{ end_date } ) && ( $query->{ start_date } ne $query->{ end_date } ) )
    {
        $ret .= ' - ' . $query->{ end_date };
    }

    return $ret;
}

# use get_weekly_date_clause or get_daily_date_clause instead
# of using this directly (get_daily_date_clause adds 6 days to
# the end date of the query).
# get clause restricting dates all dates within the query's dates.
# for some reason, postgres is really slow using ranges for dates,
# so we enumerate all of the dates instead.
# $i is the number of days to increment each date by (7 for weekly dates) and
# $date_field is the sql field to use for the in clause (eg. 'publish_week')

sub get_date_clause
{
    my ( $start_date, $end_date, $i, $date_field ) = @_;

    my $dates = [];
    for ( my $d = $start_date ; $d le $end_date ; $d = MediaWords::Util::SQL::increment_day( $d, $i ) )
    {
        push( @{ $dates }, $d );
    }

    return "${ date_field } in ( " . join( ',', map { "'$_'" } @{ $dates } ) . " )";
}

# get clause restricting dates all weekly dates within the query's dates.
# uses an in list of dates to work around slow postgres handling of
# date ranges.
sub get_weekly_date_clause
{
    my ( $query, $prefix ) = @_;

    return get_date_clause( $query->{ start_date }, $query->{ end_date }, 7, "${ prefix }.publish_week" );
}

# get clause restricting dates all daily dates within the query's dates.
# uses an in list of dates to work around slow postgres handling of
# date ranges.  adds 6 days to the query end date to capture all days
# within the last week.
sub get_daily_date_clause
{
    my ( $query, $prefix ) = @_;

    my $end_date = MediaWords::Util::SQL::increment_day( $query->{ end_date }, 6 );

    my $date_field;

    if ( $prefix )
    {
        $date_field = "${ prefix }.publish_day";
    }
    else
    {
        $date_field = 'publish_day';
    }

    return get_date_clause( $query->{ start_date }, $end_date, 1, $date_field );
}

# Gets the top 500 weekly words matching the given query.
# If no dashboard_topics_id is specified, the query requires a null dashboard_topics_id.
# start_date and end_date are rounded down to the beginning of the week.
#
# Returns a list of words in the form { stem => $s, term => $s, stem_count => $c }.
# The stem_count is normalized each week against the total counts of all top 500 words for that week
# and is averaged over the number of weeks, media sets, and dashboard topics queried.
sub _get_top_500_weekly_words_impl
{
    my ( $db, $query ) = @_;

    if ( !( $query->{ media_sets_ids } && @{ $query->{ media_sets_ids } } && $query->{ start_date } ) )
    {
        die( "media_sets_id and start_date are required" );
    }

    my $media_sets_ids_list     = MediaWords::Util::SQL::get_ids_in_list( $query->{ media_sets_ids } );
    my $dashboard_topics_clause = get_dashboard_topics_clause( $query, 'w' );
    my $date_clause             = get_weekly_date_clause( $query, 'w' );
    my $tw_date_clause          = get_weekly_date_clause( $query, 'tw' );

    # we have to divide stem_count by the number of media_sets to get the correct ratio b/c
    # the query below sum()s the stem for all media_sets
    my $stem_count_factor = @{ $query->{ media_sets_ids } };

    my $table_prefix = '';

    if ( defined( $query->{ top_500_weekly_words_table_prefix } ) )
    {
        $table_prefix = $query->{ top_500_weekly_words_table_prefix };
    }

    my $table_suffix = '';

    if ( defined( $query->{ top_500_weekly_words_table_suffix } ) )
    {
        $table_suffix = $query->{ top_500_weekly_words_table_suffix };
    }

    my $top_500_weekly_words_table       = $table_prefix . 'top_500_weekly_words' . $table_suffix;
    my $total_top_500_weekly_words_table = $table_prefix . 'total_top_500_weekly_words' . $table_suffix;

    my $words = $db->query(
        "select w.stem, min( w.term ) as term, " .
          "    sum( w.stem_count::float / tw.total_count::float )::float / ${ stem_count_factor }::float as stem_count " .
          ",    sum( w.stem_count::float) as raw_stem_count, sum (tw.total_count::float ) as total_words,              " .
          "    ${ stem_count_factor }::float as stem_count_factor                                                      " .
          "  from $top_500_weekly_words_table w, $total_top_500_weekly_words_table tw " .
          "  where w.media_sets_id in ( $media_sets_ids_list )  and " .
          "    w.media_sets_id = tw.media_sets_id and w.publish_week = tw.publish_week and $date_clause and " .
          "    tw.media_sets_id in ( $media_sets_ids_list ) and $tw_date_clause and " .
          "    $dashboard_topics_clause and coalesce( w.dashboard_topics_id, 0 ) = coalesce( tw.dashboard_topics_id, 0 ) " .
          "  group by w.stem order by sum( w.stem_count::float / tw.total_count::float )::float desc " . "  limit 500",
    )->hashes;

    return $words;
}

sub _get_json_top_500_weekly_words_for_query
{
    my ( $db, $query ) = @_;

#    ( my $words_json ) = $db->query( "SELECT decode(top_weekly_words_json, 'base64' ) FROM queries_top_weekly_words_json where queries_id = ? ",

    ( my $words_json ) = $db->query( "SELECT top_weekly_words_json FROM queries_top_weekly_words_json where queries_id = ? ",
        $query->{ queries_id } )->flat;

    if ( $words_json )
    {
        eval {
            my $words = decode_json( $words_json );
            return $words;
        };

        eval {
            utf8::upgrade( $words_json );
            my $words = decode_json( $words_json );
            return $words;
        };

        #open(MYOUTFILE, ">/tmp/json_err.out");
        #print MYOUTFILE $words_json;
        #close(MYOUTFILE);
        #say STDERR "JSON Decode error: $@ :$words_json";
    }

    return;
}

sub _store_top_500_weekly_words_for_query
{
    my ( $db, $query, $words ) = @_;

    eval {
        my $words_json = encode_json( $words );

        utf8::upgrade( $words_json );

        # open(MYOUTFILE, ">/tmp/json_stored_" . $query->{ queries_id } .  ".out");
        # print MYOUTFILE $words_json;
        # close(MYOUTFILE);

        $db->query( "DELETE FROM queries_top_weekly_words_json  where queries_id = ? ", $query->{ queries_id } );

        $db->query( "INSERT INTO queries_top_weekly_words_json (queries_id, top_weekly_words_json) VALUES ( ? , ? ) ",
            $query->{ queries_id }, $words_json );

#$db->query( "INSERT INTO queries_top_weekly_words_json (queries_id, top_weekly_words_json) VALUES ( ? , encode(?, 'base64') ) ",
#     $query->{ queries_id }, $words_json );

    };

    return;
}

sub get_top_500_weekly_words
{
    my ( $db, $query ) = @_;

    my $ret;

    my $config = MediaWords::Util::Config::get_config;

    my $disable_json = $config->{ mediawords }->{ disable_json_top_500_words_cache } eq 'yes';

    if ( $disable_json )
    {
        $ret = _get_top_500_weekly_words_impl( $db, $query );
        return $ret;
    }

    my $words = _get_json_top_500_weekly_words_for_query( $db, $query );

    if ( !$words )
    {

        $ret = _get_top_500_weekly_words_impl( $db, $query );
        _store_top_500_weekly_words_for_query( $db, $query, $ret );
    }
    else
    {

        #$ret = _get_top_500_weekly_words_impl( $db, $query );
        #die unless scalar ( @$ret ) == scalar (@$words );
        #die unless Compare($ret, $words);
        $ret = $words;
    }

    return $ret;
}

# get the list of media that include the given stem within the given single query
sub _get_media_matching_stems_single_query
{
    my ( $db, $stem, $query ) = @_;

    my $media_sets_ids_list     = MediaWords::Util::SQL::get_ids_in_list( $query->{ media_sets_ids } );
    my $dashboard_topics_clause = get_dashboard_topics_clause( $query, 'w' );
    my $date_clause             = get_daily_date_clause( $query, 'tw' );
    my $quoted_stem             = $db->dbh->quote( $stem );

    my $sql_query =
      "select ( sum(w.stem_count)::float / sum(tw.total_count)::float ) as stem_percentage, " . "    m.media_id, m.name " .
      "  from daily_words w, total_daily_words tw, media m, media_sets_media_map msmm, media_sets medium_ms " .
      "  where w.media_sets_id = tw.media_sets_id and w.publish_day = tw.publish_day and " .
      "    w.stem = $quoted_stem and $dashboard_topics_clause and " .
      "    coalesce( w.dashboard_topics_id, 0 ) = coalesce( tw.dashboard_topics_id, 0 ) and " .
      "    w.media_sets_id = medium_ms.media_sets_id and medium_ms.media_id = msmm.media_id and " .
      "    msmm.media_sets_id in ( $media_sets_ids_list ) and m.media_id = medium_ms.media_id and " . "    $date_clause " .
      "  group by m.media_id, m.name " . "  order by stem_percentage desc ";

    eval {

        #wrap in eval to work around FCGI::Stream bug.
        say STDERR "_get_media_matching_stems_single_query running query: $sql_query";
    };

    my $media = $db->query( $sql_query )->hashes;

    return $media;
}

# get the list of media that include the given stem within any of the given queries.
# include in each returned media source the following additional fields:
# { queries_ids => < list of ids of matching queries >
#   queries => <list of matching queries >
#   stem_percentage => < average percentage of stem out of total top 500 words for all matching queries >
# }
sub get_media_matching_stems
{
    my ( $db, $stem, $queries ) = @_;

    my $media_hash;
    for my $query ( @{ $queries } )
    {
        my $query_media = _get_media_matching_stems_single_query( $db, $stem, $query );

        for my $qm ( @{ $query_media } )
        {
            if ( $media_hash->{ $qm->{ media_id } } )
            {
                $media_hash->{ $qm->{ media_id } }->{ stem_percentage } += $qm->{ stem_percentage };
            }
            else
            {
                $media_hash->{ $qm->{ media_id } } = $qm;
            }
            push( @{ $media_hash->{ $qm->{ media_id } }->{ queries } },     $query );
            push( @{ $media_hash->{ $qm->{ media_id } }->{ queries_ids } }, $query->{ queries_id } );
        }
    }

    my $media = [ values( %{ $media_hash } ) ];

    for my $medium ( @{ $media } )
    {
        $medium->{ stem_percentage } /= scalar( @{ $medium->{ queries } } );
    }

    return [ sort { $b->{ stem_percentage } <=> $a->{ stem_percentage } } @{ $media } ];
}

# given a list of sentences, return a list of stories from those sentences
# sorted by publish_date and with each story the list of matching sentences
# within the { sentences } field of each story
sub _get_stories_from_sentences
{
    my ( $db, $sentences ) = @_;

    if ( !@{ $sentences } )
    {
        return [];
    }

    my $stories_ids_hash;
    map { $stories_ids_hash->{ $_->{ stories_id } } = 1 } @{ $sentences };
    my $stories_ids_list = MediaWords::Util::SQL::get_ids_in_list( [ keys( %{ $stories_ids_hash } ) ] );

    my $stories = $db->query(
        "select * from stories where stories_id in ( $stories_ids_list ) " . "  order by publish_date, stories_id" )->hashes;

    my $stories_hash;
    map { $stories_hash->{ $_->{ stories_id } } = $_ } @{ $stories };

    map { push( @{ $stories_hash->{ $_->{ stories_id } }->{ sentences } }, $_ ) } @{ $sentences };

    for my $story ( @{ $stories } )
    {
        my @sorted_sentences = sort { $a->{ sentence_number } <=> $b->{ sentence_number } } @{ $story->{ sentences } };
        $story->{ sentences } = \@sorted_sentences;
    }

    return $stories;
}

# run the given function on each query for each day each query covers
# until a total of max_results results are returned sorted by publish_date
#
# the function should be in the form sub foo { my ( $db, $query, $day, $max_results, @remaining_args ) }
# where @remaining_args passed through all args to _get_daily_results after the first four.
#
# the function should return records sorted by a publish_date field (which also must be present in
# each record).  each record must also have an { id } field that can be used to dedup
# the results between queries for each day.
sub _get_daily_results
{
    my ( $db, $queries, $function, $max_results ) = @_;

    my @function_args = @_;
    splice( @function_args, 0, 4 );

    # need to break out which queries are associated with which days
    # so that we can run $function->() in the order of days covered
    # by the union of all queries
    my $query_dates;
    for my $query ( @{ $queries } )
    {
        my $d = $query->{ start_date };
        my $end_date = MediaWords::Util::SQL::increment_day( $query->{ end_date }, 6 );
        while ( $d le $end_date )
        {
            push( @{ $query_dates->{ $d } }, $query );
            $d = MediaWords::Util::SQL::increment_day( $d );
        }
    }

    my @results = ();
    for my $d ( sort keys( %{ $query_dates } ) )
    {
        my $max_day_results = $max_results - @results;

        my $id_hash;
        for my $q ( @{ $query_dates->{ $d } } )
        {
            my $query_day_results = $function->( $db, $q, $d, $max_day_results, @function_args );
            map { $id_hash->{ $_->{ id } } = $_ } @{ $query_day_results };
        }

        push( @results, values( %{ $id_hash } ) );
        @results = sort { $a->{ publish_date } cmp $b->{ publish_date } } @results;

        if ( @results >= $max_results )
        {
            splice( @results, $max_results );
            return \@results;
        }
    }

    return \@results;
}

# get all story_sentences that match the given stem and media within the given query dashboard topic and date.
sub _get_medium_stem_sentences_day
{
    my ( $db, $query, $day, $max_sentences, $stem, $medium ) = @_;

    my $quoted_stem = $db->dbh->quote( $stem );
    my $query_sentences;
    if ( @{ $query->{ dashboard_topics_ids } } )
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );

        $query_sentences = $db->query(
            "select distinct ss.* " . "  from story_sentences ss, story_sentence_words ssw, story_sentence_words sswq, " .
              "    dashboard_topics dt " .
              "  where ss.stories_id = ssw.stories_id and ss.sentence_number = ssw.sentence_number " .
              "    and ssw.media_id = $medium->{ media_id } " . "    and ssw.stem = $quoted_stem " .
              "    and ssw.publish_day = '$day'::date " .
              "    and ssw.stories_id = sswq.stories_id and ssw.sentence_number = sswq.sentence_number " .
              "    and sswq.stem = dt.query and dt.dashboard_topics_id in ( $dashboard_topics_ids_list ) " .
              "  order by ss.publish_date, ss.stories_id, ss.sentence_number, ss.sentence asc " .
              "  limit $max_sentences" )->hashes;
    }
    else
    {
        $query_sentences =
          $db->query( "select distinct ss.* " . "  from story_sentences ss, story_sentence_words ssw " .
              "  where ss.stories_id = ssw.stories_id and ss.sentence_number = ssw.sentence_number " .
              "    and ssw.media_id = $medium->{ media_id } " . "    and ssw.stem = $quoted_stem " .
              "    and ssw.publish_day = '$day'::date " .
              "  order by ss.publish_date, ss.stories_id, ss.sentence_number, ss.sentence asc " .
              "  limit $max_sentences" )->hashes;
    }

    map { $_->{ id } = $_->{ story_sentences_id } } @{ $query_sentences };

    return $query_sentences;
}

# get all stories and sentences that match the given stem and media within the given query dashboard topic and date.
# return a list of stories sorted by publish date and with each story the list of matching
# sentences within the { sentences } field of each story
sub get_medium_stem_stories_with_sentences
{
    my ( $db, $stem, $medium, $queries ) = @_;

    my $sentences =
      _get_daily_results( $db, $queries, \&_get_medium_stem_sentences_day, MAX_QUERY_SENTENCES, $stem, $medium );

    return _get_stories_from_sentences( $db, $sentences );
}

# get all story_sentences within the given queries, dup to MAX_QUERY_SENTENCES for each query
sub _get_stem_sentences_day
{
    my ( $db, $query, $day, $max_sentences, $stem ) = @_;

    my $quoted_stem = $db->dbh->quote( $stem );

    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );

    my $query_sentences;
    if ( @{ $query->{ dashboard_topics_ids } } )
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );

        $query_sentences = $db->query(
            "select distinct ss.* " . "  from story_sentences ss, story_sentence_words ssw, story_sentence_words sswq, " .
              "    dashboard_topics dt, media_sets_media_map msmm " .
              "  where ss.stories_id = ssw.stories_id and ss.sentence_number = ssw.sentence_number " .
              "    and ssw.media_id = msmm.media_id and ssw.stem = $quoted_stem " .
              "    and ssw.publish_day = '$day'::date " .
              "    and ssw.stories_id = sswq.stories_id and ssw.sentence_number = sswq.sentence_number " .
              "    and sswq.stem = dt.query and dt.dashboard_topics_id in ( $dashboard_topics_ids_list ) " .
              "    and msmm.media_sets_id in ( $media_sets_ids_list ) " .
              "  order by ss.publish_date, ss.stories_id, ss.sentence asc " . "  limit $max_sentences" )->hashes;
    }
    else
    {
        $query_sentences = $db->query(
            "select distinct ss.* " . "  from story_sentences ss, story_sentence_words ssw, media_sets_media_map msmm " .
              "  where ss.stories_id = ssw.stories_id and ss.sentence_number = ssw.sentence_number " .
              "    and ssw.media_id = msmm.media_id and ssw.stem = $quoted_stem " .
              "    and ssw.publish_day = '$day'::date " . "    and msmm.media_sets_id in ( $media_sets_ids_list ) " .
              "  order by ss.publish_date, ss.stories_id, ss.sentence asc " . "  limit $max_sentences" )->hashes;
    }

    map { $_->{ id } = $_->{ story_sentences_id } } @{ $query_sentences };

    return $query_sentences;
}

# get all stories and sentences that match the given stem within the given queries.
# return a list of stories sorted by publish date and with each story the list of matching
# sentences within the { sentences } field of each story
sub get_stem_stories_with_sentences
{
    my ( $db, $stem, $queries ) = @_;

    my $sentences = _get_daily_results( $db, $queries, \&_get_stem_sentences_day, MAX_QUERY_SENTENCES, $stem );

    return _get_stories_from_sentences( $db, $sentences );
}

# get all story_sentences within the given query for the given day up to max_sentences
sub _get_sentences_day
{
    my ( $db, $query, $day, $max_sentences ) = @_;

    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );

    my $query_sentences;
    if ( @{ $query->{ dashboard_topics_ids } } )
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );

        $query_sentences =
          $db->query( "select distinct ss.* " .
              "  from story_sentences ss, story_sentence_words ssw, dashboard_topics dt, media_sets_media_map msmm " .
              " where ssw.publish_day = '$day'::date " . "  and ssw.media_id = msmm.media_id and ssw.stem = dt.query " .
              "  and ssw.stories_id = ss.stories_id and ssw.sentence_number = ss.sentence_number " .
              "  and dt.dashboard_topics_id in ( $dashboard_topics_ids_list ) " .
              "  and msmm.media_sets_id in ( $media_sets_ids_list ) " .
              "  order by ss.publish_date, ss.stories_id, ss.sentence_number asc " . "  limit $max_sentences" )->hashes;
    }
    else
    {
        $query_sentences =
          $db->query( "select distinct ss.* from story_sentences ss, media_sets_media_map msmm " .
              "  where ss.media_id = msmm.media_id " . "    and date_trunc( 'day', ss.publish_date )  = '$day'::date " .
              "    and msmm.media_sets_id in ( $media_sets_ids_list ) " .
              "  order by ss.publish_date, ss.stories_id, ss.sentence_number asc " . "  limit $max_sentences" )->hashes;
    }

    map { $_->{ id } = $_->{ story_sentences_id } } @{ $query_sentences };

    return $query_sentences;
}

# get all story_sentences matching any of the given queries up to a max of MAX_QUERY_SENTENCES
sub get_sentences
{
    my ( $db, $queries ) = @_;

    return _get_daily_results( $db, $queries, \&_get_sentences_day, MAX_QUERY_SENTENCES );
}

# get all stories and sentences within the given queries.
# return a list of stories sorted by publish date and with each story the list of matching
# sentences within the { sentences } field of each story
sub get_stories_with_sentences
{
    my ( $db, $queries ) = @_;

    my $sentences = get_sentences( $db, $queries );

    return _get_stories_from_sentences( $db, $sentences );
}

# get a count of media sources associated with the media sets within the cluster
sub get_number_of_media_sources
{
    my ( $db, $query ) = @_;

    my $media_set_in_list = join( ',', @{ $query->{ media_sets_ids } } );

    my ( $num_media_sources ) = $db->query(
        "select count(distinct media_id) from media_sets_media_map " . "  where media_sets_id in ( $media_set_in_list )" )
      ->flat;

    return $num_media_sources;
}

# get all the media sources that are associated with the media_sets within the query
sub get_media
{
    my ( $db, $query ) = @_;

    my $media_set_in_list = join( ',', @{ $query->{ media_sets_ids } } );

    my $media = $db->query( "select distinct( m.* ) from media m, media_sets_media_map msmm " .
          "  where m.media_id = msmm.media_id and msmm.media_sets_id in ( $media_set_in_list )" )->hashes;

    return $media;
}

# return list of term counts for the given terms within the given query in the following form:
# [ [ < date >, < term >, < count > ], ... ]

sub get_term_counts
{
    my ( $db, $query, $terms ) = @_;

    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );
    my $dashboard_topics_clause = get_dashboard_topics_clause( $query, 'dw' );
    my $date_clause = get_daily_date_clause( $query, 'dw' );

    my $stems = MediaWords::Util::Stemmer->new->stem( @{ $terms } );
    my $stems_list = join( ',', map { $db->dbh->quote( $_ ) } @{ $stems } );

    my $num_term_combinations = @{ $query->{ media_sets } } * @{ $stems };
    my ( $media_set_group, $media_set_legend );
    if ( $num_term_combinations < 5 )
    {
        $media_set_group  = ', ms.media_sets_id';
        $media_set_legend = " || ' - ' || min( ms.name )";
    }
    else
    {
        $media_set_group = $media_set_legend = '';
    }

    my $date_term_counts = [
        $db->query(
            "select dw.publish_day, dw.stem $media_set_legend as term, " .
              "      sum( dw.stem_count::float / tw.total_count::float )::float as count " .
              "  from daily_words dw, total_daily_words tw, media_sets ms " .
              "  where dw.media_sets_id in ( $media_sets_ids_list ) and dw.media_sets_id = tw.media_sets_id " .
              "    and $dashboard_topics_clause " .
              "    and coalesce( tw.dashboard_topics_id, 0 ) = coalesce( dw.dashboard_topics_id, 0 ) " .
              "    and $date_clause " . "    and dw.publish_day = tw.publish_day " . "    and dw.stem in ( $stems_list ) " .
              "    and ms.media_sets_id = dw.media_sets_id " . "  group by dw.publish_day, dw.stem $media_set_group " .
              "  order by dw.publish_day, dw.stem "
          )->arrays
    ];

    my $term_lookup = {};
    map { $term_lookup->{ $stems->[ $_ ] } = $terms->[ $_ ] } ( 0 .. $#{ $stems } );

    for my $d ( @{ $date_term_counts } )
    {
        if ( $media_set_legend )
        {
            $d->[ 1 ] =~ $term_lookup->{ $d->[ 1 ] };
        }
        else
        {
            $d->[ 1 ] =~ /([^-]*) - (.*)/;
            my ( $stem, $media_set_label ) = ( $1, $2 );
            $d->[ 1 ] = $term_lookup->{ $d->[ 1 ] } . " - $media_set_label";
        }
    }

    #print STDERR Dumper( $date_term_counts );
    return $date_term_counts;
}

# For each term, get the ratio of total mentions of that term to total mentions
# of the most common term within the time period.  Returns a list of hashes in the form:
# { stem => $s, term => $t, stem_count => $sc, max_term_ratio => $m }.
# The list will be sorted in descending order of the stem_count of each term, and
# an entry for the the most common term will be inserted as the first member of the list.
sub get_max_term_ratios
{
    my ( $db, $query, $terms, $ignore_topics ) = @_;

    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );
    my $dashboard_topics_clause =
      $ignore_topics ? "w.dashboard_topics_id is null" : get_dashboard_topics_clause( $query, 'w' );
    my $date_clause = get_weekly_date_clause( $query, 'w' );

    my $stems = MediaWords::Util::Stemmer->new->stem( @{ $terms } );
    my $stems_list = join( ',', map { $db->dbh->quote( $_ ) } @{ $stems } );

    my $max_term_count =
      $db->query( "select stem, min( term ) as term, sum( stem_count ) as stem_count, 1 as max_term_ratio " .
          "  from top_500_weekly_words w " .
          "  where media_sets_id in ( $media_sets_ids_list ) and $dashboard_topics_clause and $date_clause " .
          "  group by stem order by sum(stem_count) desc limit 1" )->hash;

    my $term_counts =
      $db->query( "select stem, sum( stem_count ) as stem_count from weekly_words w " .
          "  where media_sets_id in ( $media_sets_ids_list ) and $dashboard_topics_clause " .
          "    and stem in ( $stems_list ) and $date_clause " . "  group by stem order by stem_count desc" )->hashes;

    my $term_lookup = {};
    map { $term_lookup->{ $stems->[ $_ ] } = $terms->[ $_ ] } ( 0 .. $#{ $stems } );

    for my $i ( 0 .. $#{ $term_counts } )
    {
        my $term_count = $term_counts->[ $i ];
        $term_count->{ term }           = $term_lookup->{ $term_count->{ stem } };
        $term_count->{ max_term_ratio } = $term_count->{ stem_count } / $max_term_count->{ stem_count };
    }

    unshift( @{ $term_counts }, $max_term_count ) unless ( $term_counts->[ 0 ]->{ stem } eq $max_term_count->{ stem } );

    return $term_counts;
}

# find or create the query representing the given list of media sources based on another query
sub find_or_create_media_sub_query
{
    my ( $db, $query, $media_ids ) = @_;

    my $media_ids_list = join( ',', @{ $media_ids } );

    my $media_sets_ids =
      [ $db->query( "select media_sets_id from media_sets " . "  where media_id in ( $media_ids_list ) " )->flat ];

    return MediaWords::DBI::Queries::find_or_create_query_by_params(
        $db,
        {
            start_date           => $query->{ start_date },
            end_date             => $query->{ end_date },
            dashboard_topics_ids => $query->{ dashboard_topics_ids },
            media_sets_ids       => $media_sets_ids
        }
    );
}

# return a list of queries for each media source that is associated
# with the given query.
# return a list of media, each of which has a { query } field pointing
# to the media sub query
sub get_media_with_sub_queries
{
    my ( $db, $query ) = @_;

    my $media =
      $db->query( "select m.*, ms.media_sets_id " .
          "  from media m, media_sets_media_map msmm, queries_media_sets_map qmsm, media_sets ms " .
          "  where m.media_id = msmm.media_id and msmm.media_sets_id = qmsm.media_sets_id " .
          "    and qmsm.queries_id = $query->{ queries_id } and ms.media_id = m.media_id " . "  order by m.name" )->hashes;

    for my $medium ( @{ $media } )
    {
        $medium->{ query } = MediaWords::DBI::Queries::find_or_create_query_by_params(
            $db,
            {
                start_date           => $query->{ start_date },
                end_date             => $query->{ end_date },
                dashboard_topics_ids => $query->{ dashboard_topics_ids },
                media_sets_ids       => [ $medium->{ media_sets_id } ]
            }
        );
    }

    return $media;
}

# get word vectors for the top 500 words for each query.
# add a { vector } field to each query where the vector for each
# query is the list of the normalized counts of each word, with each word represented
# by an index value shared across the union of all words for all queries
sub add_query_vectors
{
    my ( $db, $queries ) = @_;

    my $word_hash;

    for my $query ( @{ $queries } )
    {
        my $words = MediaWords::DBI::Queries::get_top_500_weekly_words( $db, $query );

        $query->{ vector } = [ 0 ];

        for my $word ( @{ $words } )
        {
            $word_hash->{ $word->{ stem } } ||= scalar( values( %{ $word_hash } ) );
            my $word_index = $word_hash->{ $word->{ stem } };

            $query->{ vector }->[ $word_index ] = $word->{ stem_count };
        }
    }

    return $queries;
}

# add a { similarities } field that holds the cosine similarity scores between each of the
# queries to each other query.  Also add a { vectors } field as generated by add_query_vectors above.
sub add_cos_similarities
{
    my ( $db, $queries ) = @_;

    add_query_vectors( $db, $queries );

    my $num_words = List::Util::max( map { scalar( @{ $_->{ vector } } ) } @{ $queries } );

    for my $query ( @{ $queries } )
    {
        $query->{ pdl_vector } = vector_new( $num_words );

        for my $i ( 0 .. $num_words - 1 )
        {
            vector_set( $query->{ pdl_vector }, $i, $query->{ vector }->[ $i ] );
        }
    }

    for my $i ( 0 .. $#{ $queries } )
    {
        $queries->[ $i ]->{ cos }->[ $i ] = 1;

        for my $j ( $i + 1 .. $#{ $queries } )
        {
            my $sim = vector_cos_sim( $queries->[ $i ]->{ pdl_vector }, $queries->[ $j ]->{ pdl_vector } );

            $queries->[ $i ]->{ similarities }->[ $j ] = $sim;
            $queries->[ $j ]->{ similarities }->[ $i ] = $sim;
        }
    }
}

# get the list of media set options suitable for assigning to a FormFu field
sub get_media_set_options
{
    my ( $db ) = @_;

    my $media_sets = $db->query(
        "select ms.*, d.name as dashboard_name " . "  from media_sets ms, dashboard_media_sets dms, dashboards d " .
          "  where set_type = 'collection' and ms.media_sets_id = dms.media_sets_id and " .
          "    dms.dashboards_id = d.dashboards_id " . "  order by d.name, ms.name" )->hashes;
    my $media_set_options = [ map { [ $_->{ media_sets_id }, "$_->{ name } ($_->{ dashboard_name })" ] } @{ $media_sets } ];

    return $media_set_options;
}

# get the list of dashboard topic options suitable for assigning to a FormFu field
sub get_dashboard_topic_options
{
    my ( $db ) = @_;

    my $dashboard_topics =
      $db->query( "select dt.*, d.name as dashboard_name " . "  from dashboard_topics dt, dashboards d " .
          "  where dt.dashboards_id = d.dashboards_id " . "  order by d.name, dt.name" )->hashes;
    my $dashboard_topic_options =
      [ map { [ $_->{ dashboard_topics_id }, "$_->{ name } ($_->{ dashboard_name })" ] } @{ $dashboard_topics } ];

    return $dashboard_topic_options;
}

sub _get_json_country_counts_for_query
{
    my ( $db, $query ) = @_;

    ( my $country_counts_json ) =
      $db->query( "SELECT country_counts_json FROM queries_country_counts_json where queries_id = ? ",
        $query->{ queries_id } )->flat;

    if ( $country_counts_json )
    {

        #   eval {
        my $country_counts = decode_json( $country_counts_json );
        return $country_counts;

        #  };

        # eval {
        # utf8::upgrade( $country_counts_json );
        # my $country_counts = decode_json( $country_counts_json );
        # return $country_counts;

        # };
    }

    return;
}

sub _store_country_counts_for_query
{
    my ( $db, $query, $country_counts ) = @_;

    #eval {
    my $country_counts_json = encode_json( $country_counts );

    utf8::upgrade( $country_counts_json );

    $db->query( "DELETE FROM queries_country_counts_json where queries_id = ? ", $query->{ queries_id } );
    $db->query(
        "INSERT INTO queries_country_counts_json (queries_id, country_counts_json) VALUES ( ? , ? ) ",
        $query->{ queries_id },
        $country_counts_json
    );

    #};

    return;
}

# get the country counts for the given query normalized by the total daily words
# in each media set / dashboard topic
sub _get_country_counts_impl
{
    my ( $db, $query ) = @_;

    my $media_sets_ids_list       = join( ',', @{ $query->{ media_sets_ids } } );
    my $dashboard_topics_clause_2 = get_dashboard_topics_clause( $query );
    my $date_clause_2             = get_daily_date_clause( $query );

    my $shared_where_clauses =
      " $dashboard_topics_clause_2 and $date_clause_2 and media_sets_id in ( $media_sets_ids_list )";

    my $new_sql = <<"SQL";
SELECT dcc.country, SUM(dcc.country_count :: FLOAT) / total_count :: FLOAT AS country_count,
       SUM(dcc.country_count) AS country_count_raw, total_count AS total_count
FROM   (SELECT * FROM   daily_country_counts WHERE  $shared_where_clauses )  AS dcc,
       (SELECT SUM(total_count) AS total_count FROM   total_daily_words WHERE  $shared_where_clauses ) as  tdw
GROUP  BY dcc.country, tdw.total_count ORDER  BY dcc.country;  
SQL

    #say STDERR $new_sql;

    my $ret = $db->query( $new_sql )->hashes;

    return $ret;
}

sub get_country_counts
{
    my ( $db, $query ) = @_;

    my $ret = _get_json_country_counts_for_query( $db, $query );

    if ( !$ret )
    {
        $ret = _get_country_counts_impl( $db, $query );
        _store_country_counts_for_query( $db, $query, $ret );
    }

    return $ret;
}

# get a list of all stories matching the query with download texts
sub get_stories_with_text
{
    my ( $db, $query ) = @_;

    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );
    my $date_clause = get_daily_date_clause( $query, 'ssw' );

    my $stories = [];
    if ( @{ $query->{ dashboard_topics_ids } } )
    {
        my $topics = join( ',', map { $db->{ dbh }->quote( $_->{ query } ) } @{ $query->{ dashboard_topics } } );

        # I think download_texts in the distinct is slowing this down.  try a subquery for the distinct stories_id and
        # joining everything else to that
        $stories = $db->query(
"select q.stories_id, s.url, s.title, s.publish_date, m.media_id, m.name as media_name, ms.name as media_set_name, "
              . "    d.downloads_id, dt.download_text as story_text "
              . "  from stories s, media m, media_sets ms, downloads d, download_texts dt, "
              . "( select distinct ssw.stories_id, msmm.media_sets_id "
              . "    from story_sentence_words ssw, media_sets_media_map msmm "
              . "    where $date_clause and ssw.media_id = msmm.media_id "
              . "      and ssw.media_id = msmm.media_id "
              . "      and ssw.stem in ( $topics ) "
              . "      and msmm.media_sets_id in ( $media_sets_ids_list ) "
              . "  ) q "
              . "  where q.stories_id = d.stories_id and d.downloads_id = dt.downloads_id "
              . "    and q.stories_id = s.stories_id and s.media_id = m.media_id and q.media_sets_id = ms.media_sets_id "
              . "  order by ms.name, s.publish_date, s.stories_id, d.downloads_id asc limit 100000" )->hashes;
    }
    else
    {
        $stories = $db->query(
"select q.stories_id, s.url, s.title, s.publish_date, m.media_id, m.name as media_name, ms.name as media_set_name, "
              . "    d.downloads_id, dt.download_text as story_text "
              . "  from stories s, media m, media_sets ms, downloads d, download_texts dt, "
              . "( select distinct ssw.stories_id, msmm.media_sets_id "
              . "    from story_sentence_words ssw, media_sets_media_map msmm "
              . "    where $date_clause and ssw.media_id = msmm.media_id "
              . "      and ssw.media_id = msmm.media_id "
              . "      and msmm.media_sets_id in ( $media_sets_ids_list ) "
              . "  ) q "
              . "  where q.stories_id = d.stories_id and d.downloads_id = dt.downloads_id "
              . "    and q.stories_id = s.stories_id and s.media_id = m.media_id and q.media_sets_id = ms.media_sets_id "
              . "  order by ms.name, s.publish_date, s.stories_id, d.downloads_id asc limit 100000" )->hashes;
    }

    @{ $stories } || return [];

    map { delete( $_->{ downloads_id } ) } @{ $stories };

    my $concatenated_stories = [ $stories->[ 0 ] ];
    my $prev_story           = shift( @{ $stories } );

    for my $story ( @{ $stories } )
    {
        if (   ( $story->{ stories_id } == $prev_story->{ stories_id } )
            && ( $story->{ media_set_name } == $prev_story->{ media_set_name } ) )
        {
            $prev_story->{ story_text } .= "\n" . $story->{ story_text };
        }
        else
        {
            $prev_story = $story;
            push( @{ $concatenated_stories }, $story );
        }
    }

    return $concatenated_stories;
}

# get a list of all stories matching the query with download texts
sub query_is_old_version
{
    my ( $db, $query ) = @_;

    my $results = $db->query( " SELECT  enum_last (null::query_version_enum ) <> ? ", $query->{ query_version } )->flat;

    my $ret = $results->[ 0 ];
    return $ret;
}

sub query_has_sw_data
{
    my ( $db, $query ) = @_;

    my $ret = 1;

    say STDERR Dumper( $query );
    say STDERR "media_sets_ids ";
    say STDERR Dumper( $query->{ media_sets_ids } );

    foreach my $media_sets_id ( @{ $query->{ media_sets_ids } } )
    {
        my $end_date   = MediaWords::StoryVectors::get_default_story_words_end_date();
        my $start_date = MediaWords::StoryVectors::get_default_story_words_start_date();

        my $results = $db->query(
            " SELECT media_set_retains_sw_data_for_date( ?, ?, ?, ?) ",
            $media_sets_id, $query->{ start_date },
            $start_date, $end_date
        )->flat;

        say STDERR Dumper( $results );

        $ret &&= $results->[ 0 ];
    }

    return $ret;
}

1;
