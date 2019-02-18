use strict;
use warnings;

use MediaWords::CommonLibs;

use Data::Dumper;
use Readonly;
use Test::More tests => 600;
use Text::CSV_XS;

use MediaWords::TM::RetweeterScores;

Readonly my $NUM_TWITTER_USERS   => 11;
Readonly my $NUM_RETWEETED_USERS => 4;

# cached test data
my $_topic_tweet_day;
my $_topic;

sub _get_twitter_users
{
    return [ map { "twitter_user_$_" } ( 1 .. $NUM_TWITTER_USERS ) ];
}

sub _get_retweeted_users
{
    my $rt_users_a = [ map { "retweeted_user_$_" } ( 1 .. $NUM_RETWEETED_USERS ) ];
    my $rt_users_b = [ splice( @{ $rt_users_a }, scalar( @{ $rt_users_a } ) / 2 ) ];

    return ( $rt_users_a, $rt_users_b );
}

sub _get_topic($)
{
    my ( $db ) = @_;

    $_topic ||= MediaWords::Test::DB::Create::create_test_topic( $db, "retweeter_scores" );

    return $_topic;
}

# return a topic_tweet_day row if it exists.  otherwise create one along with the parent topic
sub _get_topic_tweet_day($)
{
    my ( $db ) = @_;

    return $_topic_tweet_day if ( $_topic_tweet_day );

    my $topic = _get_topic( $db );

    $_topic_tweet_day = $db->create(
        'topic_tweet_days',
        {
            topics_id      => $topic->{ topics_id },
            day            => '2017-01-01',
            tweet_count    => 1,
            num_ch_tweets  => 1,
            tweets_fetched => $Inline::Python::Boolean::true
        }
    );

    return $_topic_tweet_day;

}

# parse the number out of the twitter user name
sub twitter_user_num($)
{
    my ( $user ) = @_;

    die unless ( $user =~ /(\d+)/ );

    return $1;
}

# return true if the user is a retweeter of the given user.  we use a consistent, semi-random heuristic
# to make sure there is some enptropy in the data but that we get consistent results.
sub user_is_retweeter($$)
{
    my ( $twitter_user, $retweeted_user ) = @_;

    return ( ( twitter_user_num( $twitter_user ) % ( twitter_user_num( $retweeted_user ) + 1 ) ) == 0 ) ? 1 : 0;
}

# add rows to topic_tweets and topic_tweet_urls that mock a tweet of the given story by the given twitter_user as a
# retweet of the the given retweeted_user
sub _add_topic_tweet($$$$)
{
    my ( $db, $story, $twitter_user, $retweeted_user ) = @_;

    my $topic_tweet_day = _get_topic_tweet_day( $db );

    my $tweet_json =
      user_is_retweeter( $twitter_user, $retweeted_user )
      ? '{ "tweet": { "retweeted_status": { "user": { "screen_name": "' . $retweeted_user . '" } } } }'
      : '{ "foo": "bar" }';

    my $topic_tweet = $db->create(
        'topic_tweets',
        {
            topic_tweet_days_id => $topic_tweet_day->{ topic_tweet_days_id },
            data                => $tweet_json,
            tweet_id            => $story->{ stories_id },
            content             => "tweet for $story->{ stories_id }",
            publish_date        => '2017-01-01',
            twitter_user        => $twitter_user
        }
    );

    my $topic_tweet_url = $db->create(
        'topic_tweet_urls',
        {
            topic_tweets_id => $topic_tweet->{ topic_tweets_id },
            url             => $story->{ url }
        }
    );

    my $topic = _get_topic( $db );

    my $topic_seed_url = $db->create(
        'topic_seed_urls',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story->{ stories_id },
            url        => $story->{ url },
            processed  => $Inline::Python::Boolean::true
        }
    );
}

# add a topic_tweet to each story from an evenly distributed set of $NUM_TWITTER_USERS and $NUM_RETWEETED_USERS
sub _add_tweets_to_stories($$)
{
    my ( $db, $stories ) = @_;

    my $twitter_users = _get_twitter_users();
    my ( $rt_users_a, $rt_users_b ) = _get_retweeted_users();

    my $retweeted_users = [ @{ $rt_users_a }, @{ $rt_users_b } ];

    my $i = 0;
    for my $story ( @{ $stories } )
    {
        # $story->{ twitter_user }   = $twitter_users->[ $i % $NUM_TWITTER_USERS ];
        $story->{ twitter_user }   = $twitter_users->[ $story->{ media_id } % $NUM_TWITTER_USERS ];
        $story->{ retweeted_user } = $retweeted_users->[ $i % $NUM_RETWEETED_USERS ];

        _add_topic_tweet( $db, $story, $story->{ twitter_user }, $story->{ retweeted_user } );

        $i++;
    }

}

sub _validate_retweeter_score($)
{
    my ( $db ) = @_;

    my $label = "retweeter_scores";

    my $got_rs = $db->query( "select * from retweeter_scores" )->hash;

    my $expected_rs = {
        name      => "test_retweeter_scores",
        topics_id => _get_topic( $db )->{ topics_id },
        state     => 'created but not queued'
    };

    map { is( $got_rs->{ $_ }, $expected_rs->{ $_ }, "$label field $_" ) } ( qw/name topics_id state/ );
}

# the retweeters table should contain one row for each pair of twitter user and retweeted user for which a story
# is associated with both
sub _validate_retweeters($$)
{
    my ( $db, $stories ) = @_;

    my $label = "retweeters";

    my ( $rt_users_a, $rt_users_b ) = _get_retweeted_users();

    my $twitter_users = _get_twitter_users();

    my $expected_retweeters_lookup = {};
    for my $twitter_user ( @{ $twitter_users } )
    {
        for my $u ( @{ $rt_users_a }, @{ $rt_users_b } )
        {
            if ( user_is_retweeter( $twitter_user, $u ) )
            {
                $expected_retweeters_lookup->{ $twitter_user }->{ $u } = 1;
            }
        }
    }

    my $retweeter_score = $db->query( "select * from retweeter_scores" )->hash;
    ok( $retweeter_score, "$label retweeter_score" );

    my $got_retweeters = $db->query( "select * from retweeters" )->hashes;

    my $got_retweeters_lookup = {};
    map { $got_retweeters_lookup->{ $_->{ twitter_user } }->{ $_->{ retweeted_user } } = 1 } @{ $got_retweeters };

    while ( my ( $twitter_user, $retweeted_user_lookup ) = each( %{ $got_retweeters_lookup } ) )
    {
        for my $retweeted_user ( keys( %{ $retweeted_user_lookup } ) )
        {
            ok(
                $expected_retweeters_lookup->{ $twitter_user }->{ $retweeted_user },
                "$label found expected retweeter $twitter_user/$retweeted_user"
            );

            delete( $expected_retweeters_lookup->{ $twitter_user }->{ $retweeted_user } );
        }
    }

    for my $u ( keys( %{ $expected_retweeters_lookup } ) )
    {
        if ( !scalar( keys( %{ $expected_retweeters_lookup->{ $u } } ) ) )
        {
            delete( $expected_retweeters_lookup->{ $u } );
        }
    }

    is( scalar( keys( %{ $expected_retweeters_lookup } ) ), 0, "$label found all expected retweeters" );
}

# the retweeter_groups table should include one group for rt_users_a and another for rt_users_b, and the
# retweeter_groups_users_map table should map each of those groups to the users returned by get_retweeted_users
sub _validate_retweeter_groups($)
{
    my ( $db ) = @_;

    my $label = "retweeter_groups";

    my ( $rt_users_a, $rt_users_b ) = _get_retweeted_users();

    my $got_group_users = $db->query( <<SQL )->hashes;
select retweeter_groups_id, retweeted_user
    from retweeter_groups
        join retweeter_groups_users_map using ( retweeter_groups_id )
SQL

    is( scalar( @{ $got_group_users } ), scalar( @{ $rt_users_a } ) + scalar( @{ $rt_users_b } ), "$label count" );

    my $expected_group_users = [];
    map { push( @{ $expected_group_users }, { retweeter_groups_id => 1, retweeted_user => $_ } ) } @{ $rt_users_a };
    map { push( @{ $expected_group_users }, { retweeter_groups_id => 2, retweeted_user => $_ } ) } @{ $rt_users_b };

    rows_match( $label, $got_group_users, $expected_group_users, 'retweeted_user', [ qw/retweeter_groups_id/ ] );
}

# validate that the rows in retweeter_stories match the counts for
sub _validate_retweeter_stories($$)
{
    my ( $db, $stories ) = @_;

    my $label = "retweeter_stories";

    my $got_retweeter_stories = $db->query( "select * from retweeter_stories" )->hashes;

    my ( $rt_users_a, $rt_users_b ) = _get_retweeted_users();
    my $rt_users = [ @{ $rt_users_a }, @{ $rt_users_b } ];

    my $retweeter_stories_count = 0;

    my $expected_retweeter_stories_lookup = {};
    for my $story ( @{ $stories } )
    {
        $expected_retweeter_stories_lookup->{ $story->{ stories_id } } = {};
        for my $rt_user ( @{ $rt_users } )
        {
            if ( user_is_retweeter( $story->{ twitter_user }, $rt_user ) )
            {
                $expected_retweeter_stories_lookup->{ $story->{ stories_id } }->{ $rt_user } = 1;
                $retweeter_stories_count++;
            }
        }
    }

    is( scalar( @{ $got_retweeter_stories } ), $retweeter_stories_count, "$label count" );
    for my $rs ( @{ $got_retweeter_stories } )
    {
        my $stories_id = $rs->{ stories_id };
        my $rt_user    = $rs->{ retweeted_user };
        ok( $expected_retweeter_stories_lookup->{ $stories_id }->{ $rt_user }, "$label expected" );
    }
}

# validate that the rows in retweeter_media have the expected counts and scores
sub _validate_retweeter_media($$)
{
    my ( $db, $stories ) = @_;

    my $label = "retweeter_media";

    my $group_stories = $db->query( <<SQL )->hashes;
select rs.*, s.media_id, rgum.retweeter_groups_id
    from retweeter_stories rs
        join stories s using ( stories_id )
        join retweeter_groups_users_map rgum using ( retweeted_user )
SQL

    my $expected_count_lookup = {};
    for my $gs ( @{ $group_stories } )
    {
        $expected_count_lookup->{ $gs->{ retweeter_groups_id } }->{ $gs->{ media_id } } += $gs->{ share_count };
    }

    my $total_count_lookup = {};
    while ( my ( $retweeter_groups_id, $media_count_lookup ) = each( %{ $expected_count_lookup } ) )
    {
        my $media_ids = [ keys( %{ $media_count_lookup } ) ];
        map { $total_count_lookup->{ $retweeter_groups_id } += $media_count_lookup->{ $_ } } @{ $media_ids };
    }

    # if there are not exactly two groups, nothing else is likely to be right
    is( scalar( keys( %{ $expected_count_lookup } ) ), 2, "$label group count" );

    my ( $group_a_id, $group_b_id ) = sort { $a <=> $b } keys( %{ $expected_count_lookup } );

    my ( $group_a_total, $group_b_total ) = map { $total_count_lookup->{ $_ } } ( $group_a_id, $group_b_id );

    my $group_a_media_ids = [ keys( %{ $expected_count_lookup->{ $group_a_id } } ) ];
    my $group_b_media_ids = [ keys( %{ $expected_count_lookup->{ $group_b_id } } ) ];

    my $all_media_ids_lookup = {};
    map { $all_media_ids_lookup->{ $_ } = 1 } ( @{ $group_a_media_ids }, @{ $group_b_media_ids } );
    my $all_media_ids = [ keys( %{ $all_media_ids_lookup } ) ];

    my $expected_retweeter_media = [];
    for my $media_id ( @{ $all_media_ids } )
    {
        my $group_a_count = $expected_count_lookup->{ $group_a_id }->{ $media_id } || 0;
        my $group_b_count = $expected_count_lookup->{ $group_b_id }->{ $media_id } || 0;

        my $group_a_count_n = $group_a_count * ( $group_b_total / $group_a_total );

        my $score = 1 - ( 2 * ( $group_a_count_n / ( $group_a_count_n + $group_b_count ) ) );

        push(
            @{ $expected_retweeter_media },
            {
                media_id        => $media_id,
                group_a_count   => $group_a_count,
                group_b_count   => $group_b_count,
                group_a_count_n => $group_a_count_n,
                score           => $score
            }
        );
    }

    my $got_retweeter_media = $db->query( "select * from retweeter_media" )->hashes;

    my $fields = [ qw/media_id group_a_count group_b_count group_a_count_n score/ ];
    rows_match( $label, $got_retweeter_media, $expected_retweeter_media, 'media_id', $fields );
}

# given a file name, open the file, parse it as a csv, and return a list of hashes.
# assumes that the csv includes a header line.  If normalize_column_names is true,
# lowercase and underline column names ( 'Media type' -> 'media_type' ).  if the $file argument
# is a reference to a string, this function will parse that string instead of opening a file.
sub __get_csv_as_hashes
{
    my ( $file, $normalize_column_names ) = @_;

    my $csv = Text::CSV_XS->new( { binary => 1, sep_char => "," } )
      || die "error using CSV_XS: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    my $column_names = $csv->getline( $fh );

    if ( $normalize_column_names )
    {
        $column_names = [ map { s/ /_/g; lc( $_ ) } @{ $column_names } ];
    }

    $csv->column_names( $column_names );

    my $hashes = [];
    while ( my $hash = $csv->getline_hr( $fh ) )
    {
        push( @{ $hashes }, $hash );
    }

    return $hashes;
}

sub _validate_media_csv($)
{
    my ( $db ) = @_;

    my $retweeter_score = $db->query( "select * from retweeter_scores" )->hash || die( "no retweeter_scores found" );

    my $csv = MediaWords::TM::RetweeterScores::generate_media_csv( $db, $retweeter_score );

    my $got_rows = __get_csv_as_hashes( \$csv, 1 );

    # just do sanity test of basic retweeter_media
    my $expected_rows = $db->query( <<SQL, $retweeter_score->{ retweeter_scores_id } )->hashes;
select * from retweeter_media where retweeter_scores_id = ?
SQL

    my $fields = [ qw/retweeter_scores_id media_id group_a_count group_b_count group_a_count_n score partition/ ];
    rows_match( "generate_media_csv", $got_rows, $expected_rows, 'media_id', $fields );
}

sub _validate_matrix_csv($)
{
    my ( $db ) = @_;

    my $retweeter_score = $db->query( "select * from retweeter_scores" )->hash || die( "no retweeter_scores found" );

    my $csv = MediaWords::TM::RetweeterScores::generate_matrix_csv( $db, $retweeter_score );

    my $got_rows = __get_csv_as_hashes( \$csv, 1 );

    my $expected_rows = $db->query( <<SQL, $retweeter_score->{ retweeter_scores_id } )->hashes;
select * from retweeter_partition_matrix where retweeter_scores_id = ?
SQL

    my $fields = [ qw/retweeter_scores_id retweeter_groups_id group_name share_count group_proportion partition/ ];
    rows_match( "generate_matrix_csv", $got_rows, $expected_rows, 'retweeter_partition_matrix_id', $fields );
}

sub test_retweeter_scores($)
{
    my ( $db ) = @_;

    my $label = "test_retweeter_scores";

    srand( 2 );

    my $data = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, $NUM_TWITTER_USERS, 1, 25, $label );

    my $stories = [ grep { $_->{ stories_id } } values( %{ $data } ) ];

    _add_tweets_to_stories( $db, $stories );

    my $topic = _get_topic( $db );
    my ( $rt_users_a, $rt_users_b ) = _get_retweeted_users();

    MediaWords::TM::RetweeterScores::generate_retweeter_scores( $db, $topic, $label, $rt_users_a, $rt_users_b );

    _validate_retweeter_score( $db );
    _validate_retweeters( $db, $stories );
    _validate_retweeter_groups( $db );
    _validate_retweeter_stories( $db, $stories );
    _validate_retweeter_media( $db, $stories );

    _validate_media_csv( $db );
    _validate_matrix_csv( $db );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();
    test_retweeter_scores( $db );
}

main();
