package MediaWords::Controller::Admin::Queries;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# set of screens for creating and analyzing queries

use strict;
use warnings;
use parent 'Catalyst::Controller';

use Data::Dumper;

use MediaWords::DBI::Queries;
use MediaWords::Languages::Language;
use MediaWords::Util::CSV;

sub index : Path : Args(0)
{
    return list( @_ );
}

# list existing cluster runs
sub list : Local
{
    my ( $self, $c ) = @_;

    my $queries_ids = [
        $c->dbis->query(
            <<"EOF"
        SELECT queries_id
        FROM queries
        WHERE generate_page = 't'
        ORDER BY start_date
EOF
        )->flat
    ];

    my $queries = [ map { MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $_ ) } @{ $queries_ids } ];

    $c->stash->{ queries }  = $queries;
    $c->stash->{ template } = 'queries/list.tt2';
}

# get a query form and set the media sets and dashboard topics option values in the form
sub get_query_form
{
    my ( $self, $c, $query ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/query.yml' } );

    my $media_sets = $c->dbis->query(
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
    $form->get_field( 'media_sets_ids' )->options( $media_set_options );

    my $dashboard_topics = $c->dbis->query(
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
      [ map { [ $_->{ dashboard_topics_id }, "$_->{ name } [$_->{ language }] ($_->{ dashboard_name })" ] }
          @{ $dashboard_topics } ];
    $form->get_field( 'dashboard_topics_ids' )->options( $dashboard_topic_options );

    my $dashboards = $c->dbis->query( "SELECT * FROM dashboards ORDER BY name" )->hashes;
    my $dashboard_options = [ [ 0, '(none)' ], map { [ $_->{ dashboards_id }, $_->{ name } ] } @{ $dashboards } ];
    $form->get_field( 'dashboards_id' )->options( $dashboard_options );

    if ( $query )
    {
        map { $form->get_field( $_ )->default( $query->{ $_ } ) }
          ( qw/start_date end_date media_sets_ids dashboard_topics_ids/ );
    }

    return $form;
}

# create a new query
sub create : Local
{
    my ( $self, $c ) = @_;

    my $form = $self->get_query_form( $c );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'queries/create.tt2';
        return;
    }

    my $query = MediaWords::DBI::Queries::find_or_create_query_by_request( $c->dbis, $c->req );

    die( 'Unable to create query' ) if ( !$query );

    $c->dbis->query( "UPDATE QUERIES SET generate_page = 't' WHERE queries_id = ?", $query->{ queries_id } );

    $c->response->redirect(
        $c->uri_for( "/admin/queries/view/$query->{ queries_id }", { status_msg => 'Query created.' } ) );
}

# return url for a chart of the daily terms in the dashboard topics vs. all words for each day in the date range
sub _get_topic_chart_url
{
    my ( $self, $c, $query ) = @_;

    if ( !@{ $query->{ dashboard_topics } } )
    {
        return undef;
    }

    my $date_term_counts = $self->_get_topic_chart_url_date_term_counts( $c, $query );

    my $end_date = MediaWords::Util::SQL::increment_day( $query->{ end_date }, 6 );
    return MediaWords::Util::Chart::generate_line_chart_url_from_dates( $date_term_counts, $query->{ start_date },
        $end_date );
}

# get a csv of the date,term,count data that is used to generate a chart
sub _get_topic_chart_csv
{
    my ( $self, $c, $query ) = @_;

    if ( !@{ $query->{ dashboard_topics } } )
    {
        return undef;
    }

    my $date_term_counts = $self->_get_topic_chart_url_date_term_counts( $c, $query );

    return MediaWords::Util::CSV::get_hashes_as_encoded_csv( $date_term_counts );
}

sub _get_topic_chart_url_date_term_counts
{
    my ( $self, $c, $query ) = @_;

    my $media_sets_ids_list       = join( ',', @{ $query->{ media_sets_ids } } );
    my $dashboard_topics_ids_list = join( ',', @{ $query->{ dashboard_topics_ids } } );
    my $date_clause = MediaWords::DBI::Queries::get_daily_date_clause( $query, 'topic_words' );

    # do media set / topic combinations of there are less than 5 combinations of media set / topic
    my $num_term_combinations = @{ $query->{ media_sets } } * @{ $query->{ dashboard_topics } };
    my ( $media_set_group, $media_set_legend );
    if ( $num_term_combinations < 5 )
    {
        $media_set_group  = ', ms.media_sets_id';
        $media_set_legend = " || ' - ' || MIN( ms.name )";
    }
    else
    {
        $media_set_group = $media_set_legend = '';
    }

    my $sql = <<"EOF";
        SELECT topic_words.publish_day,
               MIN( dt.query ) $media_set_legend AS term,
               SUM( topic_words.total_count::float / all_words.total_count::float )::float AS term_count
        FROM total_daily_words AS topic_words,
             total_daily_words AS all_words,
             dashboard_topics AS dt,
             media_sets AS ms
        WHERE topic_words.media_sets_id IN ( $media_sets_ids_list )
              AND topic_words.dashboard_topics_id IN ( $dashboard_topics_ids_list )
              AND topic_words.publish_day = all_words.publish_day
              AND topic_words.media_sets_id = all_words.media_sets_id
              AND all_words.dashboard_topics_id IS NULL
              AND dt.dashboard_topics_id = topic_words.dashboard_topics_id
              AND $date_clause
              AND ms.media_sets_id = topic_words.media_sets_id
        GROUP BY topic_words.publish_day, dt.dashboard_topics_id $media_set_group
EOF

    say STDERR "$sql";
    my $date_term_counts = [ $c->dbis->query( $sql )->arrays ];

    return $date_term_counts;
}

# view a single query
sub view : Local
{
    my ( $self, $c, $queries_id ) = @_;

    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id )
      || die( "query '$queries_id' not found" );

    if ( $c->req->params->{ 'topic_chart_csv' } )
    {
        my $date_term_counts = $self->_get_topic_chart_url_date_term_counts( $c, $query );
        my $csv_hashes = [ map { { day => $_->[ 0 ], term => $_->[ 1 ], count => $_->[ 2 ] } } @{ $date_term_counts } ];
        MediaWords::Util::CSV::send_hashes_as_csv_page( $c, $csv_hashes, 'term_counts.csv' );
    }

    my $cluster_runs = $c->dbis->query( "SELECT * FROM media_cluster_runs WHERE queries_id = ?", $queries_id )->hashes;

    my $words = MediaWords::DBI::Queries::get_top_500_weekly_words( $c->dbis, $query );

    my $dashboard = $c->dbis->query( "SELECT * FROM dashboards WHERE dashboards_id = 1" )->hash;

    my $word_cloud = MediaWords::Util::WordCloud_Legacy::get_word_cloud( $c, '/queries/sentences', $words, $query );

    my $sentences_form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/term.yml',
            method           => 'get',
            action           => $c->uri_for( '/admin/queries/sentences/' )
        }
    );
    $sentences_form->get_fields( { name => 'queries_ids' } )->[ 0 ]->value( $query->{ queries_id } );

    my $terms_form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/terms.yml',
            method           => 'get',
            action           => $c->uri_for( '/admin/queries/terms/' . $query->{ queries_id } )
        }
    );

    if ( $c->req->param( 'google_table' ) )
    {
        if ( !@{ $query->{ dashboard_topics } } )
        {
            return undef;
        }

        my $date_term_counts = $self->_get_topic_chart_url_date_term_counts( $c, $query );

        my $end_date = MediaWords::Util::SQL::increment_day( $query->{ end_date }, 6 );

        my $datatable = MediaWords::Util::Chart::generate_google_data_table_from_dates(
            $date_term_counts,
            $query->{ start_date },
            MediaWords::Util::SQL::increment_day( $query->{ end_date }, 6 )
        );

        my $json_output = $datatable->output_json(

            #columns => ['date','number','string' ],
            pretty => 1,
        );

        $c->res->body( $json_output );
        return;
    }

    my ( $topic_chart_url, $max_topic_term_ratios );
    if ( @{ $query->{ dashboard_topics } } )
    {
        $topic_chart_url = $self->_get_topic_chart_url( $c, $query );
        $max_topic_term_ratios = MediaWords::DBI::Queries::get_max_term_ratios( $c->dbis, $query, 1 );
    }

    say STDERR "load template";
    $c->stash->{ query }                 = $query;
    $c->stash->{ word_cloud }            = $word_cloud;
    $c->stash->{ cluster_runs }          = $cluster_runs;
    $c->stash->{ sentences_form }        = $sentences_form;
    $c->stash->{ terms_form }            = $terms_form;
    $c->stash->{ topic_chart_url }       = $topic_chart_url;
    $c->stash->{ max_topic_term_ratios } = $max_topic_term_ratios;
    $c->stash->{ max_sentences }         = MediaWords::DBI::Queries::MAX_QUERY_SENTENCES;

    $c->stash->{ template } = 'queries/view.tt2';
}

sub view_media : Local
{
    my ( $self, $c, $queries_id ) = @_;

    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id )
      || die( "no query for '$queries_id'" );

    my $media = MediaWords::DBI::Queries::get_media_with_sub_queries( $c->dbis, $query );

    $c->stash->{ query } = $query;
    $c->stash->{ media } = $media;

    $c->stash->{ template } = 'queries/view_media.tt2';
}

# generate page with google chart of term frequencies for the given terms
sub terms : Local
{
    my ( $self, $c, $queries_id ) = @_;

    my $terms_string = $c->req->param( 'terms' ) || die( "no terms" );

    #my $terms = [ split( /[,\s]+/, $terms_string ) ];
    chomp( $terms_string );
    my $terms = [ split( /\n/, $terms_string ) ];
    my $terms_languages = [];

    foreach my $term_language ( @{ $terms } )
    {
        my ( $term, $language ) = split( ' ', $term_language );
        push( @{ $terms_languages }, { 'term' => $term, 'language' => $language } );
    }

    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id );

    my $date_term_counts = MediaWords::DBI::Queries::get_term_counts( $c->dbis, $query, $terms_languages );

    if ( $c->req->param( 'csv' ) )
    {
        my $csv_hashes = [ map { { day => $_->[ 0 ], term => $_->[ 1 ], count => $_->[ 2 ] } } @{ $date_term_counts } ];
        MediaWords::Util::CSV::send_hashes_as_csv_page( $c, $csv_hashes, "term_counts.csv" );
        return;
    }
    elsif ( $c->req->param( 'google_table' ) )
    {
        my $datatable = MediaWords::Util::Chart::generate_google_data_table_from_dates(
            $date_term_counts,
            $query->{ start_date },
            MediaWords::Util::SQL::increment_day( $query->{ end_date }, 6 )
        );

        my $json_output = $datatable->output_json(

            #columns => ['date','number','string' ],
            pretty => 1,
        );

        $c->res->body( $json_output );
        return;

    }
    else
    {

        my $max_term_ratios = MediaWords::DBI::Queries::get_max_term_ratios( $c->dbis, $query, $terms_languages );

        print STDERR "DATE TERM COUNTS:\n";
        print STDERR Dumper( $date_term_counts );

        my $term_chart_url = MediaWords::Util::Chart::generate_line_chart_url_from_dates(
            $date_term_counts,
            $query->{ start_date },
            MediaWords::Util::SQL::increment_day( $query->{ end_date }, 6 )
        );

        $c->stash->{ query }           = $query;
        $c->stash->{ term_chart_url }  = $term_chart_url;
        $c->stash->{ terms }           = $terms;
        $c->stash->{ terms_string }    = $terms_string;
        $c->stash->{ max_term_ratios } = $max_term_ratios;
        $c->stash->{ template }        = 'queries/terms.tt2';
        return;
    }
}

sub sentences : Local
{
    my ( $self, $c ) = @_;

    my $queries_ids = [ $c->req->param( 'queries_ids' ) ];
    die( "no queries_ids" ) if ( !defined( $queries_ids->[ 0 ] ) );

    my $queries =
      [ map { MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $_ ) || die( "no query $_" ) } @{ $queries_ids } ];

    my $stem      = $c->req->param( 'stem' );
    my $term      = $c->req->param( 'term' );
    my $lang_code = $c->req->param( 'language' );
    die( "no language code" ) if ( !$lang_code );

    if ( $term && !$stem )
    {
        my $lang = MediaWords::Languages::Language::language_for_code( $lang_code );
        $stem = ( $lang->stem( $term ) )->[ 0 ];
    }

    my $stories;
    if ( $stem )
    {
        $stories = MediaWords::DBI::Queries::get_stem_stories_with_sentences( $c->dbis, $stem, $queries );
    }
    else
    {
        $stories = MediaWords::DBI::Queries::get_stories_with_sentences( $c->dbis, $queries );
    }

    map { ( $_->{ medium } ) = $c->dbis->find_by_id( 'media', $_->{ media_id } ) } @{ $stories };

    my $queries_description = join( " or ", map { $_->{ description } } @{ $queries } );

    my $num_sentences = 0;
    map {
        map { $num_sentences++ }
          @{ $_->{ sentences } }
    } @{ $stories };

    $c->stash->{ queries }             = $queries;
    $c->stash->{ queries_uids }        = $queries_ids;
    $c->stash->{ queries_description } = $queries_description;
    $c->stash->{ stem }                = $stem;
    $c->stash->{ term }                = $term;
    $c->stash->{ stories }             = $stories;
    $c->stash->{ template }            = 'queries/sentences.tt2';
    $c->stash->{ max_sentences }       = MediaWords::DBI::Queries::MAX_QUERY_SENTENCES;
    $c->stash->{ num_sentences }       = $num_sentences;
}

# generate a word cloud comparing one word cloud to another
sub compare : Local
{
    my ( $self, $c ) = @_;

    my $queries_id = $c->req->param( 'queries_id' ) || die( 'no queries_id' );
    my $query_a = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id )
      || die( "Unable to find query $queries_id" );

    my $form = $self->get_query_form( $c, $query_a );

    $form->process( $c->request );

    my $queries_id_2 = $c->req->param( 'queries_id_2' );
    if ( !$queries_id_2 && !$form->submitted_and_valid() )
    {
        $c->stash->{ query_a }  = $query_a;
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'queries/compare_select.tt2';
        return;
    }

    if ( !$queries_id_2 )
    {
        my $req = $c->req;
        undef( $req->parameters->{ queries_id } );

        my $query_b = MediaWords::DBI::Queries::find_or_create_query_by_request( $c->dbis, $c->req );
        $c->response->redirect(
            $c->uri_for( "/admin/queries/compare", { queries_id => $queries_id, queries_id_2 => $query_b->{ queries_id } } )
        );
        return;
    }

    my $query_b = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id_2 )
      || die( "Unable to find query $queries_id_2" );
    my $words_a = MediaWords::DBI::Queries::get_top_500_weekly_words( $c->dbis, $query_a );
    my $words_b = MediaWords::DBI::Queries::get_top_500_weekly_words( $c->dbis, $query_b );

    my $word_cloud = MediaWords::Util::WordCloud_Legacy::get_multi_set_word_cloud(
        $c, '/queries/sentences',
        [ $words_a, $words_b ],
        [ $query_a, $query_b ]
    );

    MediaWords::Util::WordCloud_Legacy::add_query_labels( $c->dbis, $query_a, $query_b );

    eval { MediaWords::DBI::Queries::add_cos_similarities( $c->dbis, [ $query_a, $query_b ] ); };

    if ( $@ )
    {
        die "Error in add_cos_similarities $@";
        say STDERR "Error in add_cos_similarities $@";
    }

    $c->stash->{ word_cloud } = $word_cloud;
    $c->stash->{ query_a }    = $query_a;
    $c->stash->{ query_b }    = $query_b;
    $c->stash->{ template }   = 'queries/compare.tt2';
}

# download csv of all stories belonging to the query, including extracted text
sub stories : Local
{
    my ( $self, $c, $queries_id ) = @_;

    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id )
      || die( "Unable to find query $queries_id" );

    my $stories = MediaWords::DBI::Queries::get_stories_with_text( $c->dbis, $query );

    MediaWords::Util::CSV::send_hashes_as_csv_page( $c, $stories, "stories.csv" );
}

1;
