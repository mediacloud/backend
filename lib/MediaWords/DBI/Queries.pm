package MediaWords::DBI::Queries;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various routines for accessing the queries table and for querying
# the aggregate vector tables (daily/weekly/top_500_weekly)_words

use strict;

use Data::Dumper;
use Digest::MD5;
use JSON;

#use Data::Compare;

use MediaWords::Util::BigPDLVector qw(vector_new vector_set vector_cos_sim);
use MediaWords::Util::SQL;
use MediaWords::StoryVectors;
use MediaWords::Languages::Language;
use MediaWords::Solr::WordCounts;

use Readonly;

# max number of sentences to return in various get_*_stories_with_sentences functions
use constant MAX_QUERY_SENTENCES => 1000;

# get a text description for the query based on the media sets, dashboard topics, and dates.
# this is internal b/c it is set by find_query_by_id and so accessible as $query->{ description }
sub _get_description
{
    my ( $query ) = @_;

    my $description = '';

    my $dashboard        = $query->{ dashboard };
    my $media_sets       = $query->{ media_sets };
    my $dashboard_topics = $query->{ dashboard_topics };
    my $start_date       = substr( $query->{ start_date }, 0, 12 );
    my $end_date         = substr( $query->{ end_date }, 0, 12 ) if ( $query->{ end_date } );

    if ( $dashboard )
    {
        $description .= "in the " . $dashboard->{ name } . " Dashboard";
    }
    if ( @{ $media_sets } > 2 )
    {
        $description .=
          "in one of " . @{ $media_sets } . " media sources including " .
          join( " and ", map { $_->{ name } } @{ $media_sets }[ 0 .. 1 ] );
    }
    else
    {
        $description .= "in " . join( " or ", map { $_->{ name } } @{ $media_sets } );
    }

    if ( @{ $dashboard_topics } > 2 )
    {
        $description .=
          " mentioning one of " . @{ $dashboard_topics } . " topics including " .
          join( " and ", map { $_->{ name } . ' [' . $_->{ language } . ']' } @{ $dashboard_topics }[ 0 .. 1 ] );
    }
    elsif ( @{ $dashboard_topics } )
    {
        $description .=
          " mentioning " . join( " or ", map { $_->{ name } . ' [' . $_->{ language } . ']' } @{ $dashboard_topics } );
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

    _normalize_date_params( $db, $query_params );

    my $in_transaction = !$db->dbh->{ AutoCommit };

    $db->begin_work() unless ( $in_transaction );

    $db->query(
        <<"EOF",
        INSERT INTO queries (start_date, end_date, md5_signature, dashboards_id)
        VALUES ( DATE_TRUNC( 'week', ?::date ), DATE_TRUNC( 'week', ?::date ), ?, ?)
EOF
        $query_params->{ start_date },
        $query_params->{ end_date },
        $query_params->{ md5_signature },
        $query_params->{ dashboards_id } || undef
    );

    my $queries_id = $db->last_insert_id( undef, undef, 'queries', undef );

    for my $table ( 'dashboard_topics', 'media_sets' )
    {
        for my $id ( @{ $query_params->{ $table . "_ids" } } )
        {
            $db->query(
                <<"EOF",
                INSERT INTO queries_${table}_map (queries_id, ${table}_id)
                VALUES ( ?, ? )
EOF
                $queries_id, $id
            );
        }
    }

    my $query = find_query_by_id( $db, $queries_id );

    $query->{ description } = _get_description( $query );
    $db->query(
        <<"EOF",
        UPDATE queries
        SET description = ?
        WHERE queries_id = ?
EOF
        $query->{ description }, $query->{ queries_id }
    );

    $db->commit unless ( $in_transaction );

    return $query;
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
            $query->{ $table } = [
                $db->query(
                    <<"EOF"
                SELECT *
                FROM $table
                WHERE ${table}_id IN ( $ids_list )
                ORDER BY ${table}_id
EOF
                )->hashes
            ];
        }
    }
}

# set the end date to be the start date if the end date does not exist or is before the start date
sub _normalize_date_params
{
    my ( $db, $query_params ) = @_;

    if ( !$query_params->{ end_date } || ( $query_params->{ end_date } lt $query_params->{ start_date } ) )
    {
        $query_params->{ end_date } = $query_params->{ start_date };
    }

    ( $query_params->{ start_date } ) =
      $db->query( "SELECT DATE_TRUNC( 'week', ?::date )", $query_params->{ start_date } )->flat;
    ( $query_params->{ end_date } ) =
      $db->query( "SELECT DATE_TRUNC( 'week', ?::date )", $query_params->{ end_date } )->flat;
}

# get an md5 hash signature of all the distinguishing fields in the query
sub get_md5_signature
{
    my ( $db, $query_params ) = @_;

    _normalize_date_params( $db, $query_params );

    my $vals = [];

    push( @{ $vals }, substr( $query_params->{ start_date }, 0, 10 ) );
    push( @{ $vals }, substr( $query_params->{ end_date },   0, 10 ) );
    push( @{ $vals }, $query_params->{ dashboards_id } || 'none' );
    push( @{ $vals }, join( ',', sort { $a <=> $b } @{ $query_params->{ media_sets_ids } } ) );
    push( @{ $vals }, join( ',', sort { $a <=> $b } @{ $query_params->{ dashboard_topics_ids } || [] } ) );

    # print STDERR "query signature vals: " . join( '|', @{ $vals } ) . "\n";

    my $md5_signature = Digest::MD5::md5_hex( join( '|', @{ $vals } ) );

    # print STDERR "query md5 signature: $md5_signature\n";

    return $md5_signature;
}

# find a query whose signature matches the query params
sub find_query_by_params
{
    my ( $db, $query_params ) = @_;

    if ( my $dashboards_id = $query_params->{ dashboards_id } )
    {
        $query_params->{ media_sets_ids } = $db->query(
            <<"EOF",
            SELECT dms.media_sets_id
            FROM dashboard_media_sets AS dms,
                 media_sets AS ms
            WHERE dms.media_sets_id = ms.media_sets_id
                  AND ms.set_type = 'collection'
                  AND dms.dashboards_id = ?
EOF
            $dashboards_id
        )->flat;
    }

    die( "No start_date or media set" )
      unless ( $query_params->{ start_date } && ( scalar( @{ $query_params->{ media_sets_ids } } ) ) );

    my $md5_signature = get_md5_signature( $db, $query_params );

    $query_params->{ md5_signature } = $md5_signature;

    my ( $queries_id ) = $db->query(
        <<"EOF",
        SELECT queries_id
        FROM queries
        WHERE md5_signature = ?
              AND query_version = enum_last (null::query_version_enum)
EOF
        $md5_signature
    )->flat;

    return find_query_by_id( $db, $queries_id );
}

# find a query that exactly matches all of the query params or
# create one if one does not already exist.
# query params should be in the form
# {
#    start_date => $start_date,
#    end_date => $end_date,
#    media_sets_ids => [ $m, $m ],
#    dashboard_topics_ids => [ $d, $d ],
#    dashboards_id => $d
# }
# if no dashboard_topics_ids are included, then return only a query that has no
# dashboard_topics_ids associated with it.
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
        my ( $media_set_id ) = $db->query(
            <<"EOF",
            SELECT media_sets_id
            FROM media_sets
            WHERE media_id = ?
EOF
            $media_id
        )->flat;
        $ret = [ $media_set_id ];
    }
    elsif ( my $medium_name = $req->param( 'medium_name' . $param_suffix ) )
    {
        my $quoted_name = $db->dbh->quote( $medium_name );
        my ( $media_set_id ) = $db->query(
            <<"EOF"
            SELECT media_sets_id
            FROM media_sets AS ms,
                 media AS m
            WHERE m.media_id = ms.media_id
                  AND m.name = $quoted_name
EOF
        )->flat;
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

    my $dashboard_topics_ids = [ $req->param( 'dashboard_topics_ids' . $param_suffix ) ];
    $dashboard_topics_ids = [] if ( ( @{ $dashboard_topics_ids } == 1 ) && !$dashboard_topics_ids->[ 0 ] );

    my $query = find_or_create_query_by_params(
        $db,
        {
            start_date           => $req->param( 'start_date' . $param_suffix ),
            end_date             => $req->param( 'end_date' . $param_suffix ),
            media_sets_ids       => $media_sets_ids,
            dashboard_topics_ids => $dashboard_topics_ids,
            dashboards_id        => $req->param( 'dashboards_id' . $param_suffix ),
        }
    );

    return $query;
}

# return the query with the given id or undef if the id does not exist.
# attach the following fields:
# media_sets => <associated media sets>
# media_sets_ids => <associated media set ids >
# dashboards_topics => <associated dashboard topics>
# dashboard_topics_ids => <associated dashboard topic ids>
# dashboard => <associated dashboard if any>
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
                <<"EOF"
                SELECT DISTINCT m.*
                FROM $table AS m,
                     queries_${table}_map AS qm
                WHERE m.${table}_id = qm.${table}_id
                      AND qm.queries_id = $queries_id
                ORDER BY m.${table}_id
EOF
            )->hashes
        ];
        $query->{ $table . "_names" } = [ map { $_->{ name } } @{ $query->{ $table } } ];
        $query->{ $table . "_ids" }   = [ map { $_->{ $table . "_id" } } @{ $query->{ $table } } ];
    }

    if ( $query->{ dashboards_id } )
    {
        $query->{ dashboard } = $db->find_by_id( 'dashboards', $query->{ dashboards_id } );
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
        $dashboard_topic_clause = "${ prefix }" . "dashboard_topics_id IS NULL";
    }
    else
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );
        $dashboard_topic_clause = "${ prefix }" . "dashboard_topics_id IN ( $dashboard_topics_ids_list )";
    }

    return $dashboard_topic_clause;
}

sub get_dashboard_topic_names
{
    my ( $db, $query ) = @_;

    my $ret;

    $query->{ dashboard_topics_ids } ||= [];

    if ( !$query->{ dashboard_topics_ids } || !@{ $query->{ dashboard_topics_ids } } )
    {
        $ret = "all";
    }
    else
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );
        my $topic_names               = $db->query(
            <<"EOF"
            SELECT name
            FROM dashboard_topics
            WHERE dashboard_topics_id IN ( $dashboard_topics_ids_list )
EOF
        )->flat;

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

    my $media_set_names = $db->query(
        <<"EOF"
        SELECT name
        FROM media_sets
        WHERE media_sets_id IN ( $media_sets_ids_list )
EOF
    )->flat;

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

# use _get_weekly_date_clause or get_daily_date_clause instead
# of using this directly (get_daily_date_clause adds 6 days to
# the end date of the query).
# get clause restricting dates all dates within the query's dates.
# for some reason, postgres is really slow using ranges for dates,
# so we enumerate all of the dates instead.
# $i is the number of days to increment each date by (7 for weekly dates) and
# $date_field is the sql field to use for the in clause (eg. 'publish_week')

sub _get_date_clause
{
    my ( $start_date, $end_date, $i, $date_field ) = @_;

    my $dates = [];
    for ( my $d = $start_date ; $d le $end_date ; $d = MediaWords::Util::SQL::increment_day( $d, $i ) )
    {
        push( @{ $dates }, $d );
    }

    return "${ date_field } IN ( " . join( ',', map { "'$_'" } @{ $dates } ) . " )";
}

# get clause restricting dates all weekly dates within the query's dates.
# uses an in list of dates to work around slow postgres handling of
# date ranges.
sub _get_weekly_date_clause
{
    my ( $query, $prefix ) = @_;

    return _get_date_clause( $query->{ start_date }, $query->{ end_date }, 7, "${ prefix }.publish_week" );
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

    return _get_date_clause( $query->{ start_date }, $end_date, 1, $date_field );
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
    my $date_clause             = _get_weekly_date_clause( $query, 'w' );
    my $tw_date_clause          = _get_weekly_date_clause( $query, 'tw' );

 # TO DO DRL temporarily commenting this out since Inline python is commented out in MediaWords::Solr::WordCounts::word_count
 #
 # my $ret = MediaWords::Solr::WordCounts::word_count( $query, $query->{ start_date }, 500 );
 #
 # say STDERR Dumper( $ret );
 #
 # return $ret;

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
        <<"EOF"
        SELECT w.stem,
               MIN( w.term ) AS term,
               SUM( w.stem_count::float / tw.total_count::float )::float / ${ stem_count_factor }::float AS stem_count,
               SUM( w.stem_count::float) AS raw_stem_count,
               SUM( tw.total_count::float ) AS total_words,
               ${ stem_count_factor }::float AS stem_count_factor
        FROM $top_500_weekly_words_table AS w,
             $total_top_500_weekly_words_table AS tw
        WHERE w.media_sets_id IN ( $media_sets_ids_list )
              AND w.media_sets_id = tw.media_sets_id
              AND w.publish_week = tw.publish_week
              AND $date_clause
              AND tw.media_sets_id IN ( $media_sets_ids_list )
              AND $tw_date_clause
              AND $dashboard_topics_clause
              AND COALESCE( w.dashboard_topics_id, 0 ) = COALESCE( tw.dashboard_topics_id, 0 )
        GROUP BY w.stem
        ORDER BY SUM( w.stem_count::float / tw.total_count::float )::float DESC
        LIMIT 500
EOF
    )->hashes;

    return $words;
}

sub _get_json_top_500_weekly_words_for_query
{
    my ( $db, $query ) = @_;

    #     ( my $words_json ) = $db->query(<<"EOF",
    #         SELECT DECODE(top_weekly_words_json, 'base64' )
    #         FROM queries_top_weekly_words_json
    #         WHERE queries_id = ?
    # EOF

    ( my $words_json ) = $db->query(
        <<"EOF",
        SELECT top_weekly_words_json
        FROM queries_top_weekly_words_json
        WHERE queries_id = ?
EOF
        $query->{ queries_id }
    )->flat;

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

        $db->query( "DELETE FROM queries_top_weekly_words_json WHERE queries_id = ? ", $query->{ queries_id } );

        $db->query( "INSERT INTO queries_top_weekly_words_json (queries_id, top_weekly_words_json) VALUES ( ?, ? ) ",
            $query->{ queries_id }, $words_json );

        #     $db->query(<<"EOF",
        #         INSERT INTO queries_top_weekly_words_json (queries_id, top_weekly_words_json)
        #         VALUES ( ? , ENCODE(?, 'base64') )
        # EOF
        #         $query->{ queries_id }, $words_json );

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
sub _get_media_matching_stems_single_query($$$)
{
    my ( $db, $stem, $query ) = @_;

    my $media_sets_ids_list     = MediaWords::Util::SQL::get_ids_in_list( $query->{ media_sets_ids } );
    my $dashboard_topics_clause = get_dashboard_topics_clause( $query, 'w' );
    my $date_clause             = get_daily_date_clause( $query, 'tw' );
    my $quoted_stem             = $db->dbh->quote( $stem );

    my $sql_query = <<"EOF";
        SELECT ( SUM(w.stem_count)::float / SUM(tw.total_count)::float ) AS stem_percentage,
               m.media_id,
               m.name
        FROM daily_words AS w,
             total_daily_words AS tw,
             media AS m,
             media_sets_media_map AS msmm,
             media_sets AS medium_ms
        WHERE w.media_sets_id = tw.media_sets_id
              AND w.publish_day = tw.publish_day
              AND w.stem = $quoted_stem
              AND $dashboard_topics_clause
              AND COALESCE( w.dashboard_topics_id, 0 ) = COALESCE( tw.dashboard_topics_id, 0 )
              AND w.media_sets_id = medium_ms.media_sets_id
              AND medium_ms.media_id = msmm.media_id
              AND msmm.media_sets_id IN ( $media_sets_ids_list )
              AND m.media_id = medium_ms.media_id
              AND $date_clause
        GROUP BY m.media_id, m.name
        ORDER BY stem_percentage DESC
EOF

    my $media = $db->query( $sql_query )->hashes;

    return $media;
}

# get the list of media that include the given stem within any of the given queries.
# include in each returned media source the following additional fields:
# { queries_ids => < list of ids of matching queries >
#   queries => <list of matching queries >
#   stem_percentage => < average percentage of stem out of total top 500 words for all matching queries >
# }
sub get_media_matching_stems($$$)
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
        <<"EOF"
        SELECT *
        FROM stories
        WHERE stories_id IN ( $stories_ids_list )
        ORDER BY publish_date, stories_id
EOF
    )->hashes;

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
sub _get_medium_stem_sentences_day($$$$$$)
{
    my ( $db, $query, $day, $max_sentences, $stem, $medium ) = @_;

    my $quoted_stem = $db->dbh->quote( $stem );

    my $query_sentences;
    if ( @{ $query->{ dashboard_topics_ids } } )
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );

        $query_sentences = $db->query(
            <<"EOF"
            SELECT DISTINCT ss.*
            FROM story_sentences AS ss,
                 story_sentence_words AS ssw,
                 story_sentence_words AS sswq,
                 dashboard_topics AS dt
            WHERE ss.stories_id = ssw.stories_id
                  AND ss.sentence_number = ssw.sentence_number
                  AND ssw.media_id = $medium->{ media_id }
                  AND ssw.stem = $quoted_stem
                  AND ssw.publish_day = '$day'::date
                  AND ssw.stories_id = sswq.stories_id
                  AND ssw.sentence_number = sswq.sentence_number
                  AND sswq.stem = dt.query
                  AND dt.dashboard_topics_id IN ( $dashboard_topics_ids_list )
            ORDER BY ss.publish_date, ss.stories_id, ss.sentence_number, ss.sentence ASC
            LIMIT $max_sentences
EOF
        )->hashes;
    }
    else
    {
        $query_sentences = $db->query(
            <<"EOF"
            SELECT DISTINCT ss.*
            FROM story_sentences AS ss,
                 story_sentence_words AS ssw
            WHERE ss.stories_id = ssw.stories_id
                  AND ss.sentence_number = ssw.sentence_number
                  AND ssw.media_id = $medium->{ media_id }
                  AND ssw.stem = $quoted_stem
                  AND ssw.publish_day = '$day'::date
            ORDER BY ss.publish_date, ss.stories_id, ss.sentence_number, ss.sentence ASC
            LIMIT $max_sentences
EOF
        )->hashes;
    }

    map { $_->{ id } = $_->{ story_sentences_id } } @{ $query_sentences };

    return $query_sentences;
}

# get all stories and sentences that match the given stem and media within the given query dashboard topic and date.
# return a list of stories sorted by publish date and with each story the list of matching
# sentences within the { sentences } field of each story
sub get_medium_stem_stories_with_sentences($$$$)
{
    my ( $db, $stem, $medium, $queries ) = @_;

    my $sentences =
      _get_daily_results( $db, $queries, \&_get_medium_stem_sentences_day, MAX_QUERY_SENTENCES, $stem, $medium );

    return _get_stories_from_sentences( $db, $sentences );
}

# get all story_sentences within the given queries, dup to MAX_QUERY_SENTENCES for each query
sub _get_stem_sentences_day($$$$$)
{
    my ( $db, $query, $day, $max_sentences, $stem ) = @_;

    my $quoted_stem = $db->dbh->quote( $stem );

    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );

    my $query_sentences;
    if ( @{ $query->{ dashboard_topics_ids } } )
    {
        my $dashboard_topics_ids_list = MediaWords::Util::SQL::get_ids_in_list( $query->{ dashboard_topics_ids } );

        $query_sentences = $db->query(
            <<"EOF"
            SELECT DISTINCT ss.*
            FROM story_sentences AS ss,
                 story_sentence_words AS ssw,
                 story_sentence_words AS sswq,
                 dashboard_topics AS dt,
                 media_sets_media_map AS msmm
            WHERE ss.stories_id = ssw.stories_id
                  AND ss.sentence_number = ssw.sentence_number
                  AND ssw.media_id = msmm.media_id
                  AND ssw.stem = $quoted_stem
                  AND ssw.publish_day = '$day'::date
                  AND ssw.stories_id = sswq.stories_id
                  AND ssw.sentence_number = sswq.sentence_number
                  AND sswq.stem = dt.query
                  AND dt.dashboard_topics_id IN ( $dashboard_topics_ids_list )
                  AND msmm.media_sets_id IN ( $media_sets_ids_list )
            ORDER BY ss.publish_date, ss.stories_id, ss.sentence ASC
            LIMIT $max_sentences
EOF
        )->hashes;
    }
    else
    {
        $query_sentences = $db->query(
            <<"EOF"
            SELECT DISTINCT ss.*
            FROM story_sentences AS ss,
                 story_sentence_words AS ssw,
                 media_sets_media_map AS msmm
            WHERE ss.stories_id = ssw.stories_id
                  AND ss.sentence_number = ssw.sentence_number
                  AND ssw.media_id = msmm.media_id
                  AND ssw.stem = $quoted_stem
                  AND ssw.publish_day = '$day'::date
                  AND msmm.media_sets_id IN ( $media_sets_ids_list )
            ORDER BY ss.publish_date, ss.stories_id, ss.sentence ASC
            LIMIT $max_sentences
EOF
        )->hashes;
    }

    map { $_->{ id } = $_->{ story_sentences_id } } @{ $query_sentences };

    return $query_sentences;
}

# get all stories and sentences that match the given stem within the given queries.
# return a list of stories sorted by publish date and with each story the list of matching
# sentences within the { sentences } field of each story
sub get_stem_stories_with_sentences($$$)
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

        $query_sentences = $db->query(
            <<"EOF"
            SELECT DISTINCT ss.*
            FROM story_sentences AS ss,
                 story_sentence_words AS ssw,
                 dashboard_topics AS dt,
                 media_sets_media_map AS msmm
            WHERE ssw.publish_day = '$day'::date
                  AND ssw.media_id = msmm.media_id
                  AND ssw.stem = dt.query
                  AND ssw.stories_id = ss.stories_id
                  AND ssw.sentence_number = ss.sentence_number
                  AND dt.dashboard_topics_id IN ( $dashboard_topics_ids_list )
                  AND msmm.media_sets_id IN ( $media_sets_ids_list )
            ORDER BY ss.publish_date, ss.stories_id, ss.sentence_number ASC
            LIMIT $max_sentences
EOF
        )->hashes;
    }
    else
    {
        $query_sentences = $db->query(
            <<"EOF"
            SELECT DISTINCT ss.*
            FROM story_sentences AS ss,
                 media_sets_media_map AS msmm
            WHERE ss.media_id = msmm.media_id
                  AND DATE_TRUNC( 'day', ss.publish_date )  = '$day'::date
                  AND msmm.media_sets_id IN ( $media_sets_ids_list )
            ORDER BY ss.publish_date, ss.stories_id, ss.sentence_number ASC
            LIMIT $max_sentences
EOF
        )->hashes;
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
        <<"EOF"
        SELECT COUNT(distinct media_id)
        FROM media_sets_media_map
        WHERE media_sets_id IN ( $media_set_in_list )
EOF
    )->flat;

    return $num_media_sources;
}

# get all the media sources that are associated with the media_sets within the query
sub get_media
{
    my ( $db, $query ) = @_;

    my $media_set_in_list = join( ',', @{ $query->{ media_sets_ids } } );

    my $media = $db->query(
        <<"EOF"
        SELECT DISTINCT( m.* )
        FROM media AS m,
             media_sets_media_map AS msmm
        WHERE m.media_id = msmm.media_id
              AND msmm.media_sets_id IN ( $media_set_in_list )
EOF
    )->hashes;

    return $media;
}

# return list of term counts for the given terms within the given query in the following form:
# [ [ < date >, < term >, < count > ], ... ]
# '$terms_languages' is an arrayref of hashes of the following form:
#     [
#         {
#             \'language\' => \'en\',
#             \'term\' => \'health\'
#             },
#         {
#             \'language\' => \'en\',
#             \'term\' => \'tax\'
#         },
#         {
#             \'language\' => \'en\',
#             \'term\' => \'economy\'
#         }
#     ];
sub get_term_counts
{
    my ( $db, $query, $terms_languages ) = @_;

    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );
    my $dashboard_topics_clause = get_dashboard_topics_clause( $query, 'dw' );
    my $date_clause = get_daily_date_clause( $query, 'dw' );

    my @stems_clauses;    # "(stem = 'x1' AND language = 'y1') OR (stem = 'x2' AND language = 'y2') OR ..."
    my $term_lookup = {}; # 'stem [language]' => 'term [language]', 'stem [language]' => 'term [language]', ...

    for my $term_language ( @{ $terms_languages } )
    {
        my @term      = ( $term_language->{ term } );
        my $lang_code = $term_language->{ language };
        my $lang      = MediaWords::Languages::Language::language_for_code( $lang_code );
        my $stem      = $lang->stem( @term );
        $stem = @{ $stem }[ 0 ];

        # "term [language_code]"
        $term_lookup->{ $stem } = $term[ 0 ] . ' [' . $lang_code . ']';

        push( @stems_clauses, '(dw.stem = ' . $db->dbh->quote( $stem ) . ')' );
    }
    my $stems_clause = '(' . join( ' OR ', @stems_clauses ) . ')';

    my $num_term_combinations = @{ $query->{ media_sets } } * @stems_clauses;
    my ( $media_set_group, $media_set_legend );
    if ( $num_term_combinations < 6 )
    {
        $media_set_group  = ', ms.media_sets_id';
        $media_set_legend = " || ' - ' || MIN( ms.name )";
    }
    else
    {
        $media_set_group = $media_set_legend = '';
    }

    my $date_term_counts = [
        $db->query(
            <<"EOF"
        SELECT dw.publish_day,
               dw.stem $media_set_legend AS term,
               SUM( dw.stem_count::float / tw.total_count::float )::float AS count
        FROM daily_words AS dw,
             total_daily_words AS tw,
             media_sets AS ms
        WHERE dw.media_sets_id IN ( $media_sets_ids_list )
              AND dw.media_sets_id = tw.media_sets_id
              AND $dashboard_topics_clause
              AND COALESCE( tw.dashboard_topics_id, 0 ) = COALESCE( dw.dashboard_topics_id, 0 )
              AND $date_clause
              AND dw.publish_day = tw.publish_day
              AND $stems_clause
              AND ms.media_sets_id = dw.media_sets_id
        GROUP BY dw.publish_day, dw.stem $media_set_group
        ORDER BY dw.publish_day, dw.stem
EOF
        )->arrays
    ];

    for my $d ( @{ $date_term_counts } )
    {

        # "term [language_code]"
        my $term_plus_language = $d->[ 1 ] . ' [' . $d->[ 2 ] . ']';

        if ( $media_set_legend )
        {
            $d->[ 1 ] =~ $term_lookup->{ $term_plus_language };
        }
        else
        {
            $d->[ 1 ] =~ /([^-]*) - (.*)/;
            my ( $stem, $media_set_label ) = ( $1, $2 );
            $d->[ 1 ] = $term_lookup->{ $term_plus_language } . " - $media_set_label";
        }
    }

    return $date_term_counts;
}

# For each term, get the ratio of total mentions of that term to total mentions
# of the most common term within the time period.  Returns a list of hashes in the form:
# { stem => $s, term => $t, stem_count => $sc, max_term_ratio => $m }.
# The list will be sorted in descending order of the stem_count of each term, and
# an entry for the the most common term will be inserted as the first member of the list.
# (Topic) terms are located in $query->{ dashboard_topics }[...]->{ query }
sub get_max_term_ratios($$;$)
{
    my ( $db, $query, $ignore_topics ) = @_;

    # my $terms = [ map { $_->{ query } } @{ $query->{ dashboard_topics } } ];

    my @stems_clauses;    # "(stem = 'x1') OR (stem = 'x2') OR ..."
    my $term_lookup = {}; # 'stem [language]' => 'term [language]', 'stem [language]' => 'term [language]', ...
    foreach my $dashboard_topic ( @{ $query->{ dashboard_topics } } )
    {
        my $lang_code = $dashboard_topic->{ language };
        my $lang      = MediaWords::Languages::Language::language_for_code( $lang_code );
        my @term      = ( $dashboard_topic->{ query } );
        my $stem      = $lang->stem( @term );
        $stem = @{ $stem }[ 0 ];

        $term_lookup->{ $stem } = $term[ 0 ] . ' [' . $lang_code . ']';

        push( @stems_clauses, '(stem = ' . $db->dbh->quote( $stem ) . ')' );
    }
    my $stems_clause = '(' . join( ' OR ', @stems_clauses ) . ')';

    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );
    my $dashboard_topics_clause =
      $ignore_topics ? "w.dashboard_topics_id IS NULL" : get_dashboard_topics_clause( $query, 'w' );
    my $date_clause = _get_weekly_date_clause( $query, 'w' );

    my $max_term_count = $db->query(
        <<"EOF"
        SELECT stem,
               MIN( term ) AS term,
               SUM( stem_count ) AS stem_count,
               'en' AS language,
               1 AS max_term_ratio
        FROM top_500_weekly_words AS w
        WHERE media_sets_id IN ( $media_sets_ids_list )
              AND $dashboard_topics_clause
              AND $date_clause
        GROUP BY stem
        ORDER BY SUM(stem_count) DESC
        LIMIT 1
EOF
    )->hash;

    my $term_counts = $db->query(
        <<"EOF"
        SELECT stem,
               SUM( stem_count ) AS stem_count,
               'en' as language
        FROM weekly_words AS w
        WHERE media_sets_id IN ( $media_sets_ids_list )
              AND $dashboard_topics_clause
              AND $stems_clause
              AND $date_clause
        GROUP BY stem
        ORDER BY stem_count DESC
EOF
    )->hashes;

    for my $i ( 0 .. $#{ $term_counts } )
    {
        my $term_count = $term_counts->[ $i ];
        $term_count->{ term }           = $term_lookup->{ $term_count->{ stem } . ' [' . $term_count->{ language } . ']' };
        $term_count->{ max_term_ratio } = $term_count->{ stem_count } / $max_term_count->{ stem_count };
    }

    unless ($term_counts->[ 0 ]->{ stem } eq $max_term_count->{ stem }
        and $term_counts->[ 0 ]->{ language } eq $max_term_count->{ language } )
    {
        unshift( @{ $term_counts }, $max_term_count );
    }

    return $term_counts;
}

# find or create the query representing the given list of media sources based on another query
sub find_or_create_media_sub_query
{
    my ( $db, $query, $media_ids ) = @_;

    my $media_ids_list = join( ',', @{ $media_ids } );

    my $media_sets_ids = [
        $db->query(
            <<"EOF"
        SELECT media_sets_id
        FROM media_sets
        WHERE media_id IN ( $media_ids_list )
EOF
        )->flat
    ];

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

    my $media = $db->query(
        <<"EOF"
        SELECT m.*,
               ms.media_sets_id
        FROM media AS m,
             media_sets_media_map AS msmm,
             queries_media_sets_map AS qmsm,
             media_sets AS ms
        WHERE m.media_id = msmm.media_id
              AND msmm.media_sets_id = qmsm.media_sets_id
              AND qmsm.queries_id = $query->{ queries_id }
              AND ms.media_id = m.media_id
        ORDER BY m.name
EOF
    )->hashes;

    for my $medium ( @{ $media } )
    {
        $medium->{ query } = MediaWords::DBI::Queries::find_or_create_query_by_params(
            $db,
            {
                start_date           => $query->{ start_date },
                end_date             => $query->{ end_date },
                dashboard_topics_ids => $query->{ dashboard_topics_ids },
                media_sets_ids       => [ $medium->{ media_sets_id } ],
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
        <<"EOF"
        SELECT ms.*,
               d.name AS dashboard_name
        FROM media_sets AS ms,
             dashboard_media_sets AS dms,
             dashboards AS d
        WHERE set_type = 'collection'
              AND ms.media_sets_id = dms.media_sets_id
              AND dms.dashboards_id = d.dashboards_id
        ORDER BY d.name, ms.name
EOF
    )->hashes;
    my $media_set_options = [ map { [ $_->{ media_sets_id }, "$_->{ name } ($_->{ dashboard_name })" ] } @{ $media_sets } ];

    return $media_set_options;
}

# get the list of dashboard topic options suitable for assigning to a FormFu field
sub get_dashboard_topic_options
{
    my ( $db ) = @_;

    my $dashboard_topics = $db->query(
        <<"EOF"
        SELECT dt.*,
               d.name AS dashboard_name
        FROM dashboard_topics AS dt,
             dashboards AS d
        WHERE dt.dashboards_id = d.dashboards_id
        ORDER BY d.name, dt.name
EOF
    )->hashes;
    my $dashboard_topic_options =
      [ map { [ $_->{ dashboard_topics_id }, "$_->{ name } ($_->{ dashboard_name })" ] } @{ $dashboard_topics } ];

    return $dashboard_topic_options;
}

sub _get_json_country_counts_for_query($$)
{
    my ( $db, $query ) = @_;

    ( my $country_counts_json ) = $db->query(
        <<"EOF",
        SELECT country_counts_json
        FROM queries_country_counts_json
        WHERE queries_id = ?
EOF
        $query->{ queries_id }
    )->flat;

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

sub _store_country_counts_for_query($$$)
{
    my ( $db, $query, $country_counts ) = @_;

    #eval {
    my $country_counts_json = encode_json( $country_counts );

    utf8::upgrade( $country_counts_json );

    $db->query(
        <<"EOF",
        DELETE FROM queries_country_counts_json
        WHERE queries_id = ?
EOF
        $query->{ queries_id }
    );
    $db->query(
        <<"EOF",
        INSERT INTO queries_country_counts_json (queries_id, country_counts_json)
        VALUES ( ? , ? )
EOF
        $query->{ queries_id },
        $country_counts_json
    );

    #};

    return;
}

# get the country counts for the given query normalized by the total daily words
# in each media set / dashboard topic
sub _get_country_counts_impl($$)
{
    my ( $db, $query ) = @_;

    my $media_sets_ids_list       = join( ',', @{ $query->{ media_sets_ids } } );
    my $dashboard_topics_clause_2 = get_dashboard_topics_clause( $query );
    my $date_clause_2             = get_daily_date_clause( $query );

    my $shared_where_clauses =
      " $dashboard_topics_clause_2" . " AND $date_clause_2" . " AND media_sets_id IN ( $media_sets_ids_list )";

    my $new_sql = <<"EOF";
        SELECT dcc.country,
               SUM(dcc.country_count :: float) / total_count :: float AS country_count,
               SUM(dcc.country_count) AS country_count_raw,
               total_count AS total_count
        FROM (SELECT *
              FROM daily_country_counts
              WHERE $shared_where_clauses
        ) AS dcc,
             (SELECT SUM(total_count) AS total_count
              FROM total_daily_words
              WHERE $shared_where_clauses
        ) AS tdw
        GROUP BY dcc.country, tdw.total_count
        ORDER BY dcc.country
EOF

    #say STDERR $new_sql;

    my $ret = $db->query( $new_sql )->hashes;

    return $ret;
}

sub get_country_counts($$)
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

# given a list of stories with story_text fields sorted by stories_id, merge all stories
# by stories_id and concatenate the story_text fields of merged stories
sub _concatenate_story_texts
{
    my ( $stories ) = @_;

    my $concatenated_stories = [ $stories->[ 0 ] ];
    my $prev_story           = shift( @{ $stories } );

    for my $story ( @{ $stories } )
    {
        if (   ( $story->{ stories_id } == $prev_story->{ stories_id } )
            && ( $story->{ media_set_name } eq $prev_story->{ media_set_name } ) )
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
            <<"EOF"
            SELECT q.stories_id,
                   s.url,
                   s.title,
                   s.publish_date,
                   s.language,
                   m.media_id,
                   m.name AS media_name,
                   ms.name AS media_set_name,
                   d.downloads_id,
                   dt.download_text AS story_text
            FROM stories AS s,
                 media AS m,
                 media_sets AS ms,
                 downloads AS d,
                 download_texts AS dt,
                 (SELECT DISTINCT ssw.stories_id,
                                  msmm.media_sets_id
                  FROM story_sentence_words AS ssw,
                       media_sets_media_map AS msmm
                  WHERE $date_clause
                        AND ssw.media_id = msmm.media_id
                        AND ssw.stem IN ( $topics )
                        AND msmm.media_sets_id IN ( $media_sets_ids_list )
                 ) AS q
            WHERE q.stories_id = d.stories_id
                  AND d.downloads_id = dt.downloads_id
                  AND q.stories_id = s.stories_id
                  AND s.media_id = m.media_id
                  AND q.media_sets_id = ms.media_sets_id
            ORDER BY ms.name, s.publish_date, s.stories_id, d.downloads_id asc
            LIMIT 100000
EOF
        )->hashes;
    }
    else
    {
        $stories = $db->query(
            <<"EOF"
            SELECT q.stories_id,
                   s.url,
                   s.title,
                   s.publish_date,
                   s.language,
                   m.media_id,
                   m.name AS media_name,
                   ms.name AS media_set_name,
                   d.downloads_id,
                   dt.download_text AS story_text
            FROM stories AS s,
                 media AS m,
                 media_sets AS ms,
                 downloads AS d,
                 download_texts AS dt,
                 (SELECT DISTINCT ssw.stories_id,
                                  msmm.media_sets_id
                  FROM story_sentence_words AS ssw,
                       media_sets_media_map AS msmm
                  WHERE $date_clause
                        AND ssw.media_id = msmm.media_id
                        AND msmm.media_sets_id IN ( $media_sets_ids_list )
                 ) AS q
            WHERE q.stories_id = d.stories_id
                  AND d.downloads_id = dt.downloads_id
                  AND q.stories_id = s.stories_id
                  AND s.media_id = m.media_id
                  AND q.media_sets_id = ms.media_sets_id
            ORDER BY ms.name, s.publish_date, s.stories_id, d.downloads_id ASC
            LIMIT 100000
EOF
        )->hashes;
    }

    @{ $stories } || return [];

    map { delete( $_->{ downloads_id } ) } @{ $stories };

    return _concatenate_story_texts( $stories );
}

# get a list of all stories matching the query with download texts
sub query_is_old_version
{
    my ( $db, $query ) = @_;

    my $results = $db->query( "SELECT enum_last (null::query_version_enum ) <> ? ", $query->{ query_version } )->flat;

    my $ret = $results->[ 0 ];
    return $ret;
}

sub query_has_sw_data
{
    my ( $db, $query ) = @_;

    my $ret = 1;

    foreach my $media_sets_id ( @{ $query->{ media_sets_ids } } )
    {
        my $end_date   = MediaWords::StoryVectors::get_default_story_words_end_date();
        my $start_date = MediaWords::StoryVectors::get_default_story_words_start_date();

        my $sql = " SELECT media_set_retains_sw_data_for_date( ?, ?, ?, ?) ";

        my $results = $db->query( $sql, $media_sets_id, $query->{ start_date }, $start_date, $end_date )->flat;

        # say STDERR "query: '$sql'";
        # say Dumper( [ $media_sets_id, $query->{ start_date },
        # 	      $start_date, $end_date ] );

        # say STDERR Dumper( $results );

        $ret &&= $results->[ 0 ];
    }

    return $ret;
}

# return the full description of the query, without the ellipses in the { decription } field as set by _get_description
sub get_full_description
{
    my ( $query ) = @_;

    my $description;

    my $dashboard        = $query->{ dashboard };
    my $media_sets       = $query->{ media_sets };
    my $dashboard_topics = $query->{ dashboard_topics };
    my $start_date       = substr( $query->{ start_date }, 0, 12 );
    my $end_date         = substr( $query->{ end_date }, 0, 12 ) if ( $query->{ end_date } );

    if ( $dashboard )
    {
        $description = "Dashboard: $dashboard->{ name }\n";
    }

    $description .= "Media Sets: " . join( " or ", map { $_->{ name } } @{ $media_sets } ) . "\n";

    if ( @{ $dashboard_topics } )
    {
        $description .= "Topics: " . join( " or ", map { $_->{ name } } @{ $dashboard_topics } ) . "\n";
    }

    $description .= "Dates: $start_date - $end_date\n";

    return $description;
}

1;
