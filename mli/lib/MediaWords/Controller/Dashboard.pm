package MediaWords::Controller::Dashboard;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use HTML::TagCloud;
use List::Util;
use URI::Escape;

use MediaWords::Controller::Visualize;
use MediaWords::Util::Chart;
use MediaWords::Util::Translate;

use Perl6::Say;
use Data::Dumper;
use Date::Format;
use Date::Parse;

# max number of sentences to list in sentence_medium
use constant MAX_MEDIUM_SENTENCES => 100;

# number of words in a word cloud
use constant NUM_WORD_CLOUD_WORDS => 100;

sub index : Path : Args(0)
{
    return list( @_ );
}

# get the dashboard from the dashboards_id or die if dashboards_id is not set or is not a valid id
sub _get_dashboard
{
    my ( $self, $c, $dashboards_id ) = @_;

    print STDERR "dashboards_id: $dashboards_id\n";

    $dashboards_id || die( "no dashboards_id found" );

    my $dashboard = $c->dbis->find_by_id( 'dashboards', $dashboards_id ) || die( "no dashboard '$dashboards_id'" );

    return $dashboard;
}

# get list of dates that the dashboard covers
sub _get_dashboard_dates
{
    my ( $self, $c, $dashboard ) = @_;

    my ( $now, $date, $end_date ) = $c->dbis->query(
        "select date_trunc( 'week', now() ), date_trunc( 'week', start_date ), date_trunc( 'week', end_date ) " .
          "  from dashboards where dashboards_id = ?",
        $dashboard->{ dashboards_id }
    )->flat;

    $now      = substr( $now,      0, 10 );
    $date     = substr( $date,     0, 10 );
    $end_date = substr( $end_date, 0, 10 );

    my $dates;
    while ( ( $date le $end_date ) && ( $date le $now ) )
    {
        push( @{ $dates }, $date );
        $date = Date::Format::time2str( '%Y-%m-%d', Date::Parse::str2time( $date ) + ( 86400 * 7 ) + 100 );
    }

    return $dates;
}

# list media, media sets, and clusters
sub list : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $media = $c->dbis->query(
        "select distinct m.* from media m, media_sets_media_map msmm, dashboard_media_sets dms " .
          "  where m.media_id = msmm.media_id and dms.media_sets_id = msmm.media_sets_id and dms.dashboards_id = ?" .
          "  order by m.name",
        $dashboard->{ dashboards_id }
    )->hashes;

    my $collection_media_sets = $c->dbis->query(
        "select ms.* from media_sets ms, dashboard_media_sets dms " .
          "  where ms.set_type = 'collection' and ms.media_sets_id = dms.media_sets_id and dms.dashboards_id = ?" .
          "  order by ms.media_sets_id",
        $dashboard->{ dashboards_id }
    )->hashes;

    my $dashboard_topics =
      $c->dbis->query( "select * from dashboard_topics where dashboards_id = ?", $dashboard->{ dashboards_id } )->hashes;

    MediaWords::Util::Tags::assign_tag_names( $c->dbis, $collection_media_sets );

    my $dashboard_topic;
    if ( my $id = $c->req->param( 'dashboard_topics_id' ) )
    {
        $dashboard_topic = $c->dbis->find_by_id( 'dashboard_topics', $id );
    }

    my $dashboard_dates = $self->_get_dashboard_dates( $c, $dashboard );

    $c->stash->{ dashboard }             = $dashboard;
    $c->stash->{ dashboard_topic }       = $dashboard_topic;
    $c->stash->{ media }                 = $media;
    $c->stash->{ collection_media_sets } = $collection_media_sets;
    $c->stash->{ dashboard_topics }      = $dashboard_topics;
    $c->stash->{ dashboard_dates }       = $dashboard_dates;
    $c->stash->{ compare_media_sets_id } = $c->req->param( 'compare_media_sets_id' );

    $c->stash->{ template } = 'dashboard/list.tt2';
}

sub _translate_word_list
{
    my ( $self, $c, $words ) = @_;

    my $ret = [];

    for my $word ( @{ $words } )
    {
        my $translated_word = { %{ $word } };
        $translated_word->{ term } = MediaWords::Util::Translate::translate( $translated_word->{ term } );

        push @{ $ret }, $translated_word;
    }

    return $ret;
}

# return the html for a word cloud of the given words.
#
# link each word in the url to /dashboard/sentences for the current media set and
# the given term
sub get_word_cloud
{
    my ( $self, $c, $dashboard, $words, $media_set, $date, $dashboard_topic ) = @_;

    my $cloud = HTML::TagCloud->new;

    my $dashboard_topics_id = $dashboard_topic ? $dashboard_topic->{ dashboard_topics_id } : undef;

    for my $word ( @{ $words } )
    {
        my $url = $c->uri_for(
            "/dashboard/sentences/" . $dashboard->{ dashboards_id },
            {
                media_sets_id       => $media_set->{ media_sets_id },
                date                => $date,
                stem                => $word->{ stem },
                term                => $word->{ term },
                dashboard_topics_id => $dashboard_topics_id
            }
        );

        if ( $word->{ stem_count } == 0 )
        {
            warn "0 stem count for word:" . Dumper( $word );
        }
        else {
            my $term = $word->{ term };

            $cloud->add( $term, $url, $word->{ stem_count } * 100000 );
        }
    }

    $c->keep_flash( ( 'translate' ) );

    return $cloud->html;
}

# get start of week for the given date from postgres
sub get_start_of_week
{
    my ( $self, $c, $date ) = @_;

    $date || die( 'no date' );

    my ( $start_date ) = $c->dbis->query( "select date_trunc( 'week', ?::date )", $date )->flat;

    return substr( $start_date, 0, 10 );
}

# get a list of clusters relevant to the media set tag
sub get_media_set_clusters
{
    my ( $self, $c, $media_set, $dashboard ) = @_;

    my $type = $media_set->{ set_type };

    my $clusters;
    if ( $type eq 'medium' )
    {

        # for a single medium, get each of the clusters in media_sets to which the medium belongs
        $clusters = $c->dbis->query(
            "select mc.* from media_clusters mc, media_sets ms, media_sets_media_map msmm, dashboard_media_sets dms " .
              "  where mc.media_clusters_id = ms.media_clusters_id and " .
              "    msmm.media_sets_id = ms.media_sets_id and msmm.media_id = ? and " .
              "    dms.media_cluster_runs_id = mc.media_cluster_runs_id and " . "    dms.dashboards_id = ?",
            $media_set->{ media_id },
            $dashboard->{ dashboards_id }
        )->hashes;
    }
    elsif ( $type eq 'collection' )
    {

        # for a collection, get all of the clusters in the clustering run associated with the collection media_set
        $clusters = $c->dbis->query(
            "select mc.* from media_clusters mc, dashboard_media_sets dms " .
              "  where dms.media_sets_id = ? and dms.media_cluster_runs_id = mc.media_cluster_runs_id and " .
              "    dms.dashboards_id = ?",
            $media_set->{ media_sets_id },
            $dashboard->{ dashboards_id }
        )->hashes;
    }
    elsif ( $type eq 'cluster' )
    {

        # for a cluster, get all of the other clusters in the same clustering run
        $clusters = $c->dbis->query(
            "select a.* from media_clusters a, media_clusters b " .
              "  where a.media_cluster_runs_id = b.media_cluster_runs_id " . "    and b.media_clusters_id = ?",
            $media_set->{ media_clusters_id }
        )->hashes;
    }
    else
    {
        die( "unknown type '$type'" );
    }

    for my $mc ( @{ $clusters } )
    {
        $mc->{ media } = $c->dbis->query(
            "select m.* from media m, media_clusters_media_map mcmm " .
              "  where m.media_id = mcmm.media_id and mcmm.media_clusters_id = ?",
            $mc->{ media_clusters_id }
        )->hashes;

        $mc->{ internal_features } = $c->dbis->query(
            "select * from media_cluster_words " . "  where media_clusters_id = ? and internal = 't' " .
              "  order by weight desc",
            $mc->{ media_clusters_id }
        )->hashes;

        $mc->{ external_features } = $c->dbis->query(
            "select * from media_cluster_words " . "  where media_clusters_id = ? and internal = 'f' " .
              "  order by weight desc",
            $mc->{ media_clusters_id }
        )->hashes;

        $mc->{ features } = [ @{ $mc->{ external_features } }, @{ $mc->{ internal_features } } ];

        $mc->{ media_set } =
          $c->dbis->query( "select * from media_sets where media_clusters_id = ?", $mc->{ media_clusters_id } )->hash;
    }

    return $clusters;
}

# get the media_set from one of the following cgi params:
# media_sets_id, media_id, medium_name, media_clusters_id
sub get_media_set_from_params
{
    my ( $self, $c ) = @_;

    my $media_set;

    if ( my $media_sets_id = $c->req->param( 'media_sets_id' ) )
    {
        return $c->dbis->find_by_id( 'media_sets', $media_sets_id )
          || die( "no media_set for media_sets_id '$media_sets_id'" );
    }
    elsif ( my $media_id = $c->req->param( 'media_id' ) )
    {
        return $c->dbis->query( "select * from media_sets where media_id = ?", $media_id )->hash
          || die( "no media_set for media_id '$media_id'" );
    }
    elsif ( my $medium_name = $c->req->param( 'medium_name' ) )
    {
        return $c->dbis->query(
            "select ms.* from media_sets ms, media m " . "  where ms.media_id = m.media_id and m.name = ?", $medium_name )
          ->hash
          || die( "no media_set for medium_name '$medium_name'" );
    }
    elsif ( my $media_clusters_id = $c->req->param( 'media_clusters_id' ) )
    {
        return $c->dbis->query( "select * from media_sets where media_clusters_id = ?", $media_clusters_id )->hash
          || die( "no media_set for media_clusters_id '$media_clusters_id'" );
    }
    else
    {
        die( "no media_set id" );
    }
}

# return a clause restricting the dashbaord_topics_id field either to the dashboard_topics_id in
# $c->flash or to null
sub get_dashboard_topic_clause
{
    my ( $self, $dashboard_topic ) = @_;

    if ( $dashboard_topic && $dashboard_topic->{ dashboard_topics_id } )
    {
        return "dashboard_topics_id = $dashboard_topic->{ dashboard_topics_id }";
    }
    else
    {
        return "dashboard_topics_id is null";
    }
}

# compare the words of the two media sets and return two lists of words: words_a, words_b
# words_a is the list of words that appear proportionally more in media_set_a than in media_set_b
# and words_b is the converse
sub compare_media_set_words
{
    my ( $self, $c, $media_set_a, $media_set_b, $date, $dashboard_topic ) = @_;

    my $db = $c->dbis;

    my $dashboard_topic_clause = $self->get_dashboard_topic_clause( $dashboard_topic );

    # compute min_stem_count_* from the max stem_count in the set, divided by some factor.
    # we use this number instead of 0 for words with no stem_count to avoid finding only
    # prevalent words that only appear in one source
    my ( $max_stem_count_a ) = $db->query(
        "select max( stem_count ) " . "  from ( select stem_count from top_500_weekly_words_normalized " .
          "      where media_sets_id = ? and publish_week = date_trunc( 'week', ?::date ) " .
          "        and $dashboard_topic_clause ) q ",
        $media_set_a->{ media_sets_id },
        $date
    )->flat;
    my ( $max_stem_count_b ) = $db->query(
        "select max( stem_count ) " . "  from ( select stem_count from top_500_weekly_words_normalized " .
          "      where media_sets_id = ? and publish_week = date_trunc( 'week', ?::date ) " .
          "        and $dashboard_topic_clause ) q ",
        $media_set_b->{ media_sets_id },
        $date
    )->flat;

    my $min_stem_count_a = $max_stem_count_a / 50;
    my $min_stem_count_b = $max_stem_count_a / 50;

    # setup equations for relative prevalence here just to make the query below cleaner.
    # the coalesce stuff is necessary to assign non-null values to words not in one of the sets
    my $pr_a =
      "( ( coalesce( a.stem_count, 0 ) * sqrt ( coalesce( a.stem_count, 0 ) ) ) / " .
      "  greatest( $min_stem_count_a, coalesce( b.stem_count, 0 ) ) )";
    my $pr_b =
      "( ( coalesce( b.stem_count, 0 ) * sqrt ( coalesce( b.stem_count, 0 ) ) ) / " .
      "  greatest( $min_stem_count_b, coalesce( a.stem_count, 0 ) ) )";

    my $words_a = $c->dbis->query(
        "select $pr_a as stem_count, $pr_b as stem_count_b, " .
          "    coalesce( a.stem, b.stem ) as stem, coalesce( a.term, b.term ) as term " . "  from " .
          "    ( select * from top_500_weekly_words_normalized " .
          "        where media_sets_id = ? and publish_week = date_trunc('week', ?::date ) " .
          "          and $dashboard_topic_clause ) a " . "    full outer join " .
          "    ( select * from top_500_weekly_words_normalized " .
          "        where media_sets_id = ? and publish_week = date_trunc('week', ?::date ) " .
          "          and $dashboard_topic_clause ) b " . "    on ( a.stem = b.stem ) " . "  order by stem_count desc",
        $media_set_a->{ media_sets_id },
        $date, $media_set_b->{ media_sets_id }, $date
    )->hashes;

    # sort and then deep copy words_a into words_b to avoid having to run the query again
    my $words_b = [
        map { my $h = { %{ $_ } }; $h->{ stem_count } = $h->{ stem_count_b }; $h }
        sort { $b->{ stem_count_b } <=> $a->{ stem_count_b } } @{ $words_a }
    ];

    $#{ $words_a } = List::Util::min( $#{ $words_a }, NUM_WORD_CLOUD_WORDS - 1 );
    $#{ $words_b } = List::Util::min( $#{ $words_b }, NUM_WORD_CLOUD_WORDS - 1 );

    return ( $words_a, $words_b );
}

# display a comparison page for the media_sets_id and compare_media_sets_id
sub compare : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $compare_media_sets_id = $c->req->param( 'compare_media_sets_id' );
    my $media_set_a = $c->dbis->find_by_id( 'media_sets', $compare_media_sets_id )
      || die( "Unable to find compare_media_set '$compare_media_sets_id'" );

    my $media_set_b = $self->get_media_set_from_params( $c );

    my $date = $self->get_start_of_week( $c, $c->req->param( 'date' ) );

    my $dashboard_topics_id = $c->req->param( 'dashboard_topics_id' ) || 0;
    my $dashboard_topic = $c->dbis->find_by_id( 'dashboard_topics', $dashboard_topics_id );

    my ( $words_a, $words_b ) = $self->compare_media_set_words( $c, $media_set_a, $media_set_b, $date, $dashboard_topic );

    my $word_cloud_a = $self->get_word_cloud( $c, $dashboard, $words_a, $media_set_a, $date, $dashboard_topic );
    my $word_cloud_b = $self->get_word_cloud( $c, $dashboard, $words_b, $media_set_b, $date, $dashboard_topic );

    $c->stash->{ dashboard }       = $dashboard;
    $c->stash->{ dashboard_topic } = $dashboard_topic;
    $c->stash->{ media_set_a }     = $media_set_a;
    $c->stash->{ media_set_b }     = $media_set_b;
    $c->stash->{ word_cloud_a }    = $word_cloud_a;
    $c->stash->{ word_cloud_b }    = $word_cloud_b;
    $c->stash->{ date }            = $date;

    $c->stash->{ template } = 'dashboard/compare.tt2';
}

# view the dashboard page for a media set
sub view : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $translate = $self->_set_translate_state( $c );

    if ( $c->req->param( 'compare_media_sets_id' ) )
    {
        return $self->compare( $c, $dashboards_id );
    }

    my $dashboard_topics_id = $c->req->param( 'dashboard_topics_id' ) || 0;
    my $dashboard_topic = $c->dbis->find_by_id( 'dashboard_topics', $dashboard_topics_id );
    my $dashboard_topic_clause = $self->get_dashboard_topic_clause( $dashboard_topic );

    my $media_set = $self->get_media_set_from_params( $c );

    my $date = $self->get_start_of_week( $c, $c->req->param( 'date' ) );

    my $words_query =
      ( "select * from top_500_weekly_words_normalized " . "  where media_sets_id = $media_set->{ media_sets_id } " .
          "    and not is_stop_stem( 'long', stem ) " . "    and publish_week = date_trunc('week', '$date'::date) " .
          "    and $dashboard_topic_clause " . "  order by stem_count desc limit " . NUM_WORD_CLOUD_WORDS );

    #say STDERR "SQL query: '$words_query'";

    my $words = $c->dbis->query( $words_query )->hashes;

    if ( scalar( @{ $words } ) == 0 )
    {
        my $error_message =
          "No words found within the week starting on $date \n" . "for media_sets_id $media_set->{ media_sets_id}";

        $c->{ stash }->{ error_message } = $error_message;
        return $self->list( $c, $dashboards_id );
    }

    if ( $c->flash->{ translate } )
    {
        $words = $self->_translate_word_list( $c, $words );
    }

    $c->keep_flash( ( 'translate' ) );

    my $word_cloud = $self->get_word_cloud( $c, $dashboard, $words, $media_set, $date, $dashboard_topic );

    my $term_chart_url =
      MediaWords::Util::Chart::get_daily_term_chart_url( $c->dbis, $media_set, $date, 7, $words, $dashboard_topic_clause );

    my $clusters = $self->get_media_set_clusters( $c, $media_set, $dashboard );

    $c->stash->{ dashboard }             = $dashboard;
    $c->stash->{ dashboard_topic }       = $dashboard_topic;
    $c->stash->{ media_set }             = $media_set;
    $c->stash->{ word_cloud }            = $word_cloud;
    $c->stash->{ term_chart_url }        = $term_chart_url;
    $c->stash->{ clusters }              = $clusters;
    $c->stash->{ date }                  = $date;
    $c->stash->{ compare_media_sets_id } = $c->req->param( 'compare_media_sets_id' );

    $c->stash->{ template } = 'dashboard/view.tt2';
}

sub _set_translate_state
{
    my ( $self, $c ) = @_;
    my $translate = $c->req->param( 'translate' );

    if ( !defined( $translate ) )
    {
        $translate = $c->flash->{ translate };
    }

    $translate ||= 0;

    $c->flash->{ translate } = $translate;

    return $translate;
}

# get the sentences that include the given word for the given medium on the given day.
# if the dashboard_topics_id is set in the user session, restrict to the topic query
sub get_medium_day_sentences
{
    my ( $c, $media_id, $stem, $dashboard_topic, $date_string, $days, $num_sentences ) = @_;

    if ( $dashboard_topic )
    {
        return $c->dbis->query( "select distinct ss.publish_date, ss.stories_id, ss.sentence, s.url " .
"  from story_sentences ss, story_sentence_words ssw, story_sentence_words sswq, stories s, dashboard_topics dt "
              . "  where ss.stories_id = ssw.stories_id and ss.sentence_number = ssw.sentence_number "
              . "    and s.stories_id = ssw.stories_id and ssw.media_id = ? and ssw.stem = ? "
              . "    and date_trunc('day', ssw.publish_date) = ( ?::date + interval '$days days' ) "
              . "    and ssw.stories_id = sswq.stories_id and ssw.sentence_number = sswq.sentence_number "
              . "    and sswq.stem = dt.query and dt.dashboard_topics_id = ? "
              . "  order by ss.publish_date, ss.stories_id, ss.sentence asc "
              . "  limit $num_sentences",
            $media_id, $stem, $date_string, $dashboard_topic->{ dashboard_topics_id } )->hashes;
    }
    else
    {
        return $c->dbis->query( "select distinct ss.publish_date, ss.stories_id, ss.sentence, s.url " .
              "  from story_sentences ss, story_sentence_words ssw, stories s " .
              "  where ss.stories_id = ssw.stories_id and ss.sentence_number = ssw.sentence_number " .
              "    and s.stories_id = ssw.stories_id " . "    and ssw.media_id = ? " . "    and ssw.stem = ? " .
              "    and date_trunc('day', ssw.publish_date) = ( ?::date + interval '$days days' ) " .
              "  order by ss.publish_date, ss.stories_id, ss.sentence asc " . "  limit $num_sentences",
            $media_id, $stem, $date_string )->hashes;
    }
}

sub get_medium_day_stories
{
    my ( $c, $media_id, $stem, $dashboard_topic, $date_string, $days, $num_sentences ) = @_;

    my $stories = [];

    # we should make a num_stories somewhere, but for now we'll just use num_sentences

    if ( $dashboard_topic )
    {
        $stories = $c->dbis->query(
            "select distinct ssw.stories_id, s.title, s.url, s.publish_date
            from story_sentence_words ssw, story_sentence_words sswq, stories s, dashboard_topics dt
            where ssw.media_id=? and ssw.stem=?
              and date_trunc('day', ssw.publish_date) = ( ?::date + interval '$days days' )
              and dt.dashboard_topics_id=?
              and s.stories_id=ssw.stories_id
              and sswq.stem=dt.query
              and ssw.stories_id=sswq.stories_id
              and ssw.sentence_number=sswq.sentence_number
            order by s.publish_date asc
            limit $num_sentences",
            $media_id, $stem, $date_string, $dashboard_topic->{ dashboard_topics_id }
        )->hashes;
    }
    else
    {
        $stories = $c->dbis->query(
            "select distinct ssw.stories_id, s.title, s.url, s.publish_date
            from story_sentence_words ssw, stories s 
            where ssw.media_id=? and ssw.stem=?
              and date_trunc('day', ssw.publish_date) = ( ?::date + interval '$days days' )
              and s.stories_id=ssw.stories_id
            order by s.publish_date asc
            limit $num_sentences",
            $media_id, $stem, $date_string
        )->hashes;
    }

    for my $story ( @{ $stories } )
    {
        my $id        = $story->{ stories_id };
        my $sentences = $c->dbis->query( "
            select distinct ss.sentence
            from story_sentences ss, story_sentence_words ssw
            where ssw.stem=? and ss.stories_id=?
              and ss.stories_id=ssw.stories_id
              and ss.sentence_number=ssw.sentence_number
            order by ss.sentence asc
            limit $num_sentences
            ", $stem, $id )->flat;
        $story->{ sentences } = $sentences;

        $story->{ publish_date } = time2str( "%a %b %e, %Y", str2time( $story->{ publish_date } ) );
    }

    return $stories;
}

# list the sentence matching the given term for the given medium for the given week
sub sentences_medium : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $media_id = $c->req->param( 'media_id' ) || die( 'no media_id' );
    my $stem     = $c->req->param( 'stem' )     || die( 'no stem' );
    my $term     = $c->req->param( 'term' )     || die( 'no term' );

    my $translate = $self->_set_translate_state( $c );

    my $date_string = $self->get_start_of_week( $c, $c->req->param( 'date' ) );

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    my $dashboard_topics_id = $c->req->param( 'dashboard_topics_id' ) || 0;
    my $dashboard_topic = $c->dbis->find_by_id( 'dashboard_topics', $dashboard_topics_id );
    my $dashboard_topic_clause = $self->get_dashboard_topic_clause( $dashboard_topic );

    ( $medium->{ stem_percentage } ) = $c->dbis->query(
        "select ( sum(d.stem_count)::float / sum(t.total_count)::float ) * ( count(*) / 7::float )  as stem_percentage " .
          "  from daily_words d, total_daily_words t, media_sets ms " .
          "  where d.media_sets_id = t.media_sets_id and d.publish_day = t.publish_day and " .
          "    d.$dashboard_topic_clause and t.$dashboard_topic_clause and " .
          "    d.media_sets_id = ms.media_sets_id and ms.media_id = ? and " .
"    t.publish_day between date_trunc('week', ?::date) and ( date_trunc('week', ?::date) + interval '6 days' ) and "
          . "    d.stem = ? ",
        $media_id, $date_string, $date_string, $stem )->flat;

    # get the sentences in chunks of a day apiece so that we can quit early if we get MAX_MEDIUM_SENTENCES
    my $sentences = [];
    my $stories   = [];

    for my $days ( 0 .. 6 )
    {
        my $day_sentences =
          get_medium_day_sentences( $c, $media_id, $stem, $dashboard_topic, $date_string, $days,
            ( MAX_MEDIUM_SENTENCES - @{ $sentences } ) );

        push( @{ $sentences }, @{ $day_sentences } );

        if ( @{ $sentences } >= MAX_MEDIUM_SENTENCES )
        {
            last;
        }

        # get title for each story
        for my $sentence ( @{ $sentences } )
        {
            my $id    = $sentence->{ stories_id };
            my $title = $c->dbis->query( "select title from stories where stories_id=$id" )->flat->[ 0 ];
            $sentence->{ title } = $title;
        }
    }

    for my $days ( 0 .. 6 )
    {
        my $day_stories =
          get_medium_day_stories( $c, $media_id, $stem, $dashboard_topic, $date_string, $days,
            ( MAX_MEDIUM_SENTENCES - @{ $stories } ) );

        push( @{ $stories }, @{ $day_stories } );

        if ( @{ $stories } >= MAX_MEDIUM_SENTENCES )
        {
            last;
        }
    }

    $c->keep_flash( ( 'translate' ) );

    $c->stash->{ dashboard }       = $dashboard;
    $c->stash->{ dashboard_topic } = $dashboard_topic;
    $c->stash->{ term }            = $term;
    $c->stash->{ translated_term } = MediaWords::Util::Translate::translate( $term );
    $c->stash->{ medium }          = $medium;
    $c->stash->{ date }            = $date_string;
    $c->stash->{ sentences }       = $sentences;
    $c->stash->{ params }          = $c->req->params;
    $c->stash->{ template }        = 'dashboard/sentences_medium.tt2';
    $c->stash->{ stories }         = $stories;
}

# list the sentence counts for each medium in the media set
# if the media set is a medium, just redirect to sentence_medium
sub sentences : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $stem = $c->req->param( 'stem' ) || die( 'no stem' );
    my $term = $c->req->param( 'term' ) || die( 'no term' );

    my $dashboard_topics_id = $c->req->param( 'dashboard_topics_id' ) || 0;
    my $dashboard_topic = $c->dbis->find_by_id( 'dashboard_topics', $dashboard_topics_id );
    my $dashboard_topic_clause = $self->get_dashboard_topic_clause( $dashboard_topic );

    my $date = $self->get_start_of_week( $c, $c->req->param( 'date' ) );

    my $media_set = $self->get_media_set_from_params( $c );

    if ( $media_set->{ set_type } eq 'medium' )
    {
        $c->res->redirect(
            $c->uri_for(
                '/dashboard/sentences_medium/' . $dashboards_id,
                {
                    media_id            => $media_set->{ media_id },
                    date                => $date,
                    term                => $term,
                    stem                => $stem,
                    dashboard_topics_id => $dashboard_topics_id
                }
            )
        );
        return;
    }

    my $media = $c->dbis->query(
        "select ( sum(d.stem_count)::float / sum(t.total_count)::float ) * ( count(*) / 7::float ) as stem_percentage, " .
          "    m.media_id, m.name " . "  from daily_words d, total_daily_words t, media m, " .
          "    media_sets_media_map msmm, media_sets medium_ms " .
          "  where d.media_sets_id = t.media_sets_id and d.publish_day = t.publish_day and " .
          "    d.$dashboard_topic_clause and t.$dashboard_topic_clause and " .
          "    d.media_sets_id = medium_ms.media_sets_id and medium_ms.media_id = msmm.media_id and " .
          "    msmm.media_sets_id = ? and m.media_id = medium_ms.media_id and " .
"    t.publish_day between date_trunc('week', ?::date) and ( date_trunc('week', ?::date) + interval '6 days' ) and "
          . "    d.stem = ? "
          . "  group by m.media_id, m.name "
          . "  order by stem_percentage desc ",
        $media_set->{ media_sets_id },
        $date, $date, $stem
    )->hashes;

    $c->stash->{ dashboard }       = $dashboard;
    $c->stash->{ dashboard_topic } = $dashboard_topic;
    $c->stash->{ media }           = $media;
    $c->stash->{ media_set }       = $media_set;
    $c->stash->{ date }            = $date;
    $c->stash->{ stem }            = $stem;
    $c->stash->{ term }            = $term;

    $c->stash->{ template } = 'dashboard/sentences.tt2';
}

1;
