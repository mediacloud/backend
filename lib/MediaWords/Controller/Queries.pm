package MediaWords::Controller::Queries;

# set of screens for creating and analyzing queries

use strict;
use warnings;
use parent 'Catalyst::Controller';

use Data::Dumper;
use Perl6::Say;

use MediaWords::DBI::Queries;
use MediaWords::Util::CSV;

sub index : Path : Args(0)
{
    return list( @_ );
}

# list existing cluster runs
sub list : Local
{
    my ( $self, $c ) = @_;
    
    my $queries_ids = [ $c->dbis->query( "select queries_id from queries where generate_page = 't' order by start_date" )->flat ];
    
    my $queries = [ map { MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $_ ) } @{ $queries_ids } ];
        
    $c->stash->{ queries } = $queries;
    $c->stash->{ template } = 'queries/list.tt2';
}

# create a new dashboard
sub create : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/query.yml',
            method           => 'post',
            action           => $c->uri_for( '/queries/create' ),
        }
    );

    my $media_sets = $c->dbis->query( 
        "select ms.*, d.name as dashboard_name " . 
        "  from media_sets ms, dashboard_media_sets dms, dashboards d " . 
        "  where set_type = 'collection' and ms.media_sets_id = dms.media_sets_id and " .
        "    dms.dashboards_id = d.dashboards_id " .
        "  order by d.name, ms.name" )->hashes;
    my $media_set_options = [ map { [ $_->{ media_sets_id }, "$_->{ name } ($_->{ dashboard_name })" ] } @{ $media_sets } ];
    my $media_set_field = $form->get_fields( { name => 'media_sets_ids' } )->[ 0 ];
    $media_set_field->options( $media_set_options );

    my $dashboard_topics = $c->dbis->query(
        "select dt.*, d.name as dashboard_name " . 
        "  from dashboard_topics dt, dashboards d " . 
        "  where dt.dashboards_id = d.dashboards_id " .
        "  order by d.name, dt.name" )->hashes;
    my $dashboard_topic_options = [ map { [ $_->{ dashboard_topics_id }, "$_->{ name } ($_->{ dashboard_name })" ] } @{ $dashboard_topics } ];
    my $dashboard_topic_field = $form->get_fields( { name => 'dashboard_topics_ids' } )->[ 0 ];
    $dashboard_topic_field->options( $dashboard_topic_options );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'queries/create.tt2';
        return;
    }

    my $query = MediaWords::DBI::Queries::find_or_create_query_by_params( 
        $c->dbis, 
        { start_date => $c->req->param( 'start_date' ), 
          end_date => $c->req->param( 'end_date' ),
          media_sets_ids => [ $c->req->param( 'media_sets_ids') ], 
          dashboard_topics_ids => [ $c->req->param( 'dashboard_topics_ids' ) ] } );
          
    $c->dbis->query( "update queries set generate_page = 't' where queries_id = ?", $query->{ queries_id } );

    $c->response->redirect( $c->uri_for( "/queries/view/$query->{ queries_id }", { status_msg => 'Query created.' } ) );
}

# return url for a chart of the daily terms in the dashboard topics vs. total top 500 words for each day in the date range
sub _get_topic_chart_url
{
    my ( $self, $c, $query ) = @_;
    
    if ( !@{ $query->{ dashboard_topics } } )
    {
        return undef;
    }
    
    my $dashboard_topics_ids_list = join( ',', @{ $query->{ dashboard_topics_ids } } );
    
    my $date_term_counts = [ $c->dbis->query(
        "select topic_words.publish_day, min( dt.query ), " . 
        "    sum( topic_words.total_count::float / all_words.total_count::float )::float as term_count " .
        "  from total_daily_words topic_words, total_daily_words all_words, dashboard_topics dt " .
        "  where topic_words.dashboard_topics_id in ( $dashboard_topics_ids_list ) " . 
        "    and topic_words.publish_day = all_words.publish_day and topic_words.media_sets_id = all_words.media_sets_id " . 
        "    and all_words.dashboard_topics_id is null and dt.dashboard_topics_id = topic_words.dashboard_topics_id " .
        "    and topic_words.publish_day between date_trunc( 'week', '$query->{ start_date }'::date ) " . 
        "    and date_trunc( 'week', '$query->{ end_date }'::date)  + interval '6 days'" .
        "  group by topic_words.publish_day, dt.dashboard_topics_id " )->arrays ];
        
    return MediaWords::Util::Chart::generate_line_chart_url_from_dates( $date_term_counts );
}

# view a single query
sub view : Local
{
    my ( $self, $c, $queries_id ) = @_;
    
    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id ) || die( "query '$queries_id' not found" );
    
    my $cluster_runs = $c->dbis->query( "select * from media_cluster_runs where queries_id = ?", $queries_id )->hashes;
    
    my $words = MediaWords::DBI::Queries::get_top_500_weekly_words( $c->dbis, $query );
    
    my $dashboard = $c->dbis->query( "select * from dashboards where dashboards_id = 1" )->hash;
        
    my $word_cloud_base_url = "/queries/sentences/$query->{ queries_id }";
    my $word_cloud = MediaWords::Util::WordCloud::get_word_cloud( $c, $word_cloud_base_url, $words, $query );  
    
    my $sentences_form = $c->create_form( {
        load_config_file => $c->path_to() . '/root/forms/term.yml',
        method           => 'get',
        action           => $c->uri_for( '/queries/sentences/' . $query->{ queries_id } ) } );
        
    my $terms_form = $c->create_form( {
        load_config_file => $c->path_to() . '/root/forms/terms.yml',
        method           => 'get',
        action           => $c->uri_for( '/queries/terms/' . $query->{ queries_id } ) } );
        
    my $topic_chart_url = $self->_get_topic_chart_url( $c, $query );
    
    $c->stash->{ query } = $query;
    $c->stash->{ word_cloud } = $word_cloud;
    $c->stash->{ cluster_runs } = $cluster_runs;
    $c->stash->{ sentences_form } = $sentences_form;
    $c->stash->{ terms_form } = $terms_form;
    $c->stash->{ topic_chart_url } = $topic_chart_url;
    
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

sub terms : Local
{
    my ( $self, $c, $queries_id ) = @_;
    
    my $terms_string = $c->req->param( 'terms' ) || die( "no terms" );

    my $terms = [ split( /[,\s]+/, $terms_string ) ];
    
    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id );

    my $date_term_counts = MediaWords::DBI::Queries::get_term_counts( $c->dbis, $query, $terms );
    
    if ( $c->req->param( 'csv' ) )
    {
        my $csv_hashes = [ map { { day => $_->[ 0 ], term => $_->[ 1 ], count => $_->[ 2 ] } } @{ $date_term_counts } ];
        MediaWords::Util::CSV::send_hashes_as_csv_page( $c, $csv_hashes, "term_counts.csv" );
        return;
    }

    my $term_chart_url = MediaWords::Util::Chart::generate_line_chart_url_from_dates( 
        $date_term_counts, $query->{ start_date }, MediaWords::Util::SQL::increment_day( $query->{ end_date }, 6 ) );

    $c->stash->{ query } = $query;
    $c->stash->{ term_chart_url } = $term_chart_url;
    $c->stash->{ terms } = $terms;
    $c->stash->{ terms_string } = $terms_string;
    $c->stash->{ template } = 'queries/terms.tt2';
}

sub sentences : Local
{
    my ( $self, $c, $queries_id ) = @_;
    
    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id ) || die( "query '$queries_id' not found" );
    
    my $stem = $c->req->param( 'stem' );
    my $term = $c->req->param( 'term' );
    
    if ( $term && !$stem ) 
    {
        $stem = ( MediaWords::Util::Stemmer->new->stem( $term ) )->[ 0 ];
    }

    my $stories;
    if ( $stem )
    {
        $stories = MediaWords::DBI::Queries::get_stem_stories_with_sentences( $c->dbis, $stem, [ $query ] );
    } 
    else {
        $stories = MediaWords::DBI::Queries::get_stories_with_sentences( $c->dbis, [ $query ] );
    }   
    
    map { ( $_->{ medium } ) = $c->dbis->find_by_id( 'media', $_->{ media_id } ) } @{ $stories };
    
    # my $queries_description = join( " or ", map { $_->{ description } } @{ $queries } );
    my $queries_description = $query->{ description };
    
    $c->stash->{ query } = $query;
    $c->stash->{ queries_description } = $queries_description;
    $c->stash->{ stem } = $stem;
    $c->stash->{ term } = $term;
    $c->stash->{ stories } = $stories;
    $c->stash->{ template } = 'queries/sentences.tt2';
}

1;
