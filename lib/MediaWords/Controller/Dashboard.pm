package MediaWords::Controller::Dashboard;

use strict;
use warnings;

#use parent 'Catalyst::Controller';
use parent 'Catalyst::Controller::HTML::FormFu';

use HTML::TagCloud;
use List::Util;
use Net::SMTP;
use Number::Format qw(:subs);
use URI::Escape;
use List::Util qw (max min maxstr minstr reduce sum);
use List::MoreUtils qw/:all/;

use MediaWords::Controller::Visualize;
use MediaWords::Util::Chart;
use MediaWords::Util::Config;
use MediaWords::Util::Countries;
use MediaWords::Util::Stemmer;

#use MediaWords::Util::Translate;

use MediaWords::Util::WordCloud;

use Perl6::Say;
use Data::Dumper;
use Date::Format;
use Date::Parse;
use Switch 'Perl6';
use Locale::Country;
use Date::Calc qw(:all);
use JSON;
use Time::HiRes;
use XML::Simple qw(:strict);
use Dir::Self;
use Readonly;
use File::stat;

# statics for state between print_time() calls
my $_start_time;
my $_last_time;

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    my $dashboards_id = $self->_default_dashboards_id( $c );

    $self->_redirect_to_default_page( $c, $dashboards_id );
}

sub get_default_dashboards_id
{
    my ( $dbis ) = @_;

    my ( $dashboards_id ) = $dbis->query( "select dashboards_id from dashboards order by dashboards_id limit 1" )->flat;

    say STDERR Dumper( $dashboards_id );
    return $dashboards_id;
}

sub _default_dashboards_id
{
    my ( $self, $c ) = @_;

    return get_default_dashboards_id( $c->dbis );
}

sub _yesterday_date_string
{
    my ( $self, $c ) = @_;
    my ( $yesterday ) = $c->dbis->query( "select (now()::date - interval '1 day')::date" )->flat;
    return $yesterday;
}

# redirect to the default view page, which is the page for the default media set
# as determined by mediaowrds:defualt_media_set in mediawords.yml) and the second
# to last week (which should be the last full week)
sub _redirect_to_default_page
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    #TODO pick a different media_sets_id if this one isn't in the dashboard
    my $media_sets_id = $config->{ mediawords }->{ default_media_set } || 1;

    my ( $max_date ) = $c->dbis->query(
        " SELECT publish_week::date FROM total_top_500_weekly_words where media_sets_id = ?  " .
          "   group by publish_week::date order by publish_week::date desc limit 1 offset 1",
        $media_sets_id
    )->flat();

    if ( !$max_date )
    {
        ( $max_date ) = $c->dbis->query(
            " SELECT publish_week::date FROM total_top_500_weekly_words where media_sets_id = ?  " .
              "   group by publish_week::date order by publish_week::date desc limit 1",
            $media_sets_id
        )->flat();
    }

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );
    my $date = maxstr( grep { $_ le $max_date } @{ $self->_get_dashboard_dates( $c, $dashboard ) } )
      || die( "no valid date found" );

    my $query =
      MediaWords::DBI::Queries::find_or_create_query_by_params( $c->dbis,
        { media_sets_ids => [ $media_sets_id ], start_date => $date } );

    my $redirect = $c->uri_for( '/dashboard/view/' . $dashboards_id, { q1 => $query->{ queries_id } } );

    $c->res->redirect( $redirect );
}

# get the dashboard from the dashboards_id or die if dashboards_id is not set or is not a valid id
sub _get_dashboard
{
    my ( $self, $c, $dashboards_id ) = @_;

    return get_dashboard( $c->dbis, $dashboards_id );
}

sub get_dashboard
{
    my ( $dbis, $dashboards_id ) = @_;

    $dashboards_id || die( "no dashboards_id found" );

    my $dashboard = $dbis->find_by_id( 'dashboards', $dashboards_id ) || die( "no dashboard '$dashboards_id'" );

    return $dashboard;
}

sub _get_author_name
{
    my ( $self, $c, $authors_id ) = @_;

    return if !$authors_id;

    my $author = $c->dbis->find_by_id( 'authors', $authors_id );

    return $author->{ author_name };
}

# get list of dates that the dashboard covers
sub _get_dashboard_dates
{
    my ( $self, $c, $dashboard ) = @_;

    my $yesterday = $self->_yesterday_date_string( $c );

    my $end_date = minstr( $dashboard->{ end_date }, $yesterday );

    my $date_exists_query =
      "select 1 from total_top_500_weekly_words t, dashboard_media_sets dms " .
      "  where t.publish_week = ? and dms.dashboards_id = $dashboard->{ dashboards_id } " .
      "    and dms.media_sets_id = t.media_sets_id limit 1";

    my $start_date;
    for ( my $d = $dashboard->{ start_date } ; $d le $end_date ; $d = MediaWords::Util::SQL::increment_day( $d, 1 ) )
    {
        if ( $c->dbis->query( $date_exists_query, $d )->hash )
        {
            $start_date = $d;
            last;
        }
    }

    return [] if ( !$start_date );

    my $all_dates;
    for ( my $d = $start_date ; $d le $end_date ; $d = MediaWords::Util::SQL::increment_day( $d, 7 ) )
    {
        push( @{ $all_dates }, $d );
    }

    my $valid_dates = [];
    for my $d ( @{ $all_dates } )
    {
        push( @{ $valid_dates }, $d ) if ( $c->dbis->query( $date_exists_query, $d )->hash );
    }

    return $valid_dates;
}

sub _get_author_words
{
    my ( $self, $c, $media_set_num, $authors_id ) = @_;

    my $date = $c->req->param( 'date' . $media_set_num );

    $authors_id += 0;

    return $c->dbis->query(
        "select stem, min(term) as term, sum( stem_count ) as stem_count from top_500_weekly_author_words " .
          "  where not is_stop_stem( 'long', stem ) and authors_id = $authors_id " .
          "    and publish_week = date_trunc('week', '$date'::date) " . "  group by stem " .
          "  order by stem_count desc limit " . MediaWords::Util::WordCloud::NUM_WORD_CLOUD_WORDS )->hashes;
}

sub _get_country_counts
{
    my ( $self, $c, $query ) = @_;

    my $country_counts = MediaWords::DBI::Queries::get_country_counts( $c->dbis, $query );

    my $ret;
    foreach my $country_count ( @$country_counts )
    {
        my $country_code =
          MediaWords::Util::Countries::get_country_code_for_stemmed_country_name( $country_count->{ country } );

        die Dumper( $country_count ) unless defined $country_code && $country_count->{ country_count };

        $ret->{ $country_code } = $country_count->{ country_count };
    }

    return $ret;
}

# get an xml or csv list of the top 500 words for the given set of queries
sub get_word_list : Local
{
    my ( $self, $c ) = @_;

    my $queries_ids = [ $c->req->param( 'queries_ids' ) ];

    my $words = [];
    for my $queries_id ( @{ $queries_ids } )
    {
        my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id );
        my $query_words = MediaWords::DBI::Queries::get_top_500_weekly_words( $c->dbis, $query );

        map { $_->{ query_id } = $queries_id; $_->{ query_description } = $query->{ description } } @{ $query_words };
        push( @{ $words }, @{ $query_words } );
    }

    my $output_format = $c->req->param( 'format' );

    my $response_body;
    if ( $output_format eq 'xml' )
    {
        my $xml = XMLout(
            { word => $words },
            RootName => 'word_list',
            KeyAttr  => [],
            XMLDecl  => 1,
            NoAttr   => 1
        );

        $response_body = $xml;

        $c->response->header( "Content-Disposition" => "attachment;filename=word_list.xml" );
        $c->response->content_type( 'text/xml' );
    }
    else
    {
        my $fields = [ qw ( stem term stem_count query_id query_description ) ];

        my $csv = Class::CSV->new( fields => $fields );

        $csv->add_line( $fields );

        foreach my $word ( @$words )
        {
            $csv->add_line( $word );
        }

        $response_body = $csv->string;
        $c->response->header( "Content-Disposition" => "attachment;filename=word_list.csv" );
        $c->response->content_type( 'text/csv' );
    }

    $c->response->content_length( length( $response_body ) );
    $c->response->body( $response_body );

    return;
}

# get an xml or csv list of the top 500 words for the given set of queries
sub country_counts_csv : Local
{
    my ( $self, $c ) = @_;

    my $queries_id = $c->req->param( 'queries_id' );

    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id );
    my $country_counts = $self->_get_country_counts( $c, $query );
    my $country_count_csv_array = $self->_country_counts_to_csv_array( $country_counts );

    my $response_body = join "\n", ( 'country_code,value', @{ $country_count_csv_array } );
    $c->response->header( "Content-Disposition" => "attachment;filename=country_list.csv" );
    $c->response->content_type( 'text/csv' );
    $c->response->content_length( length( $response_body ) );
    $c->response->body( $response_body );

    return;
}

sub get_country_counts_all_dates : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard_topic;

    my $media_set_num = 1;

    if ( my $id = $c->req->param( "dashboard_topics_id$media_set_num" ) )
    {
        $dashboard_topic = $c->dbis->find_by_id( 'dashboard_topics', $id );
    }

    my $dashboard_topic_clause = $self->get_dashboard_topic_clause( $dashboard_topic );

    print_time( "got dashboard_topic_clause" );

    my $media_set = $self->get_media_set_from_params( $c, $media_set_num );

    print_time( "got start_of_week" );

    #$self->validate_dashboard_topic_date( $c, $dashboard_topic, $date );

    #print_time( "validated dashboard_topic_date" );

    my $start_date = $c->req->param( "date1" );
    my $end_date   = $c->req->param( "date2" );

    my $date_query_part = '';

    my $country_counts;

    if ( $start_date && $end_date )
    {
        my $country_count_query =
"SELECT   media_sets_id, dashboard_topics_id, country, SUM(country_count) as country_count, publish_day FROM daily_country_counts "
          . "WHERE  media_sets_id = $media_set->{ media_sets_id }  and $dashboard_topic_clause  "
          . " AND  publish_day >= ? AND publish_day <= ?                                        "
          . "GROUP BY publish_day, media_sets_id, dashboard_topics_id, country order by publish_day, country;";

        #say STDERR "SQL query: '$country_count_query'";

        print_time( "starting country_count_query" );

        $country_counts = $c->dbis->query( $country_count_query, $start_date, $end_date )->hashes;
    }
    else
    {
        my $country_count_query =
"SELECT   media_sets_id, dashboard_topics_id, country, SUM(country_count) as country_count, publish_day FROM daily_country_counts "
          . "WHERE  media_sets_id = $media_set->{ media_sets_id }  and $dashboard_topic_clause  "
          . "GROUP BY publish_day, media_sets_id, dashboard_topics_id, country order by publish_day, country;";

        #say STDERR "SQL query: '$country_count_query'";

        print_time( "starting country_count_query" );

        $country_counts = $c->dbis->query( $country_count_query )->hashes;
    }

    print_time( "finished country_count_query" );

    my $ret = {};

    say STDERR "total country count rows: " . scalar( @$country_counts );

    foreach my $country_count ( @$country_counts )
    {
        my $country_code_2 =
          MediaWords::Util::Countries::get_country_code_for_stemmed_country_name( $country_count->{ country } );
        die unless defined $country_code_2;

        my $country_code_3 = uc( country_code2code( $country_code_2, LOCALE_CODE_ALPHA_2, LOCALE_CODE_ALPHA_3 ) );

        $country_count->{ country_code } = $country_code_3;
        $country_count->{ time }         = $country_count->{ publish_day };
        $country_count->{ value }        = $country_count->{ country_count };
    }

    say STDERR "updated country count rows";

    my $data_level = $c->req->param( "data_level" );

    my $fields = [ qw ( country_code value time ) ];

    my $csv = Class::CSV->new( fields => $fields );

    $csv->add_line( $fields );

    my $count_hash = {};
    foreach my $country_count ( @$country_counts )
    {
        my $count_date = $country_count->{ time };

        #say STDERR "$count_date";
        my $country_code = $country_count->{ country_code };
        my ( $year, $month, $day ) = split '-', $count_date;

        #say STDERR Dumper([( $year,$month,$day)]);

        my ( $week_of_year, ) = Week_of_Year( $year, $month, $day );

        #say STDERR "week_of_year is $week_of_year";

        #say STDERR Dumper([Monday_of_Week($week_of_year, $year)]);

        my $new_time;

        if ( $data_level eq 'week' )
        {
            my $monday_of_week = sprintf( "%d-%02d-%02d", ( Monday_of_Week( $week_of_year, $year ) ) );
            say STDERR "$count_date truncated to $monday_of_week";

            #say STDERR Dumper( [ str2time( $monday_of_week ) ] );
            $new_time = $monday_of_week;
        }
        else
        {
            $new_time = sprintf( "%d-%02d-%02d", $year, $month, $day );
        }

        if ( defined( $count_hash->{ $new_time }->{ $country_code } ) )
        {
            $count_hash->{ $new_time }->{ $country_code }->{ value } += $country_count->{ value };
        }
        else
        {
            $count_hash->{ $new_time }->{ $country_code } = $country_count;
        }
        $count_hash->{ $new_time }->{ $country_code }->{ time } = $new_time;

    }

    # scale the data
    foreach my $count_time ( keys %$count_hash )
    {

        my $count_hash_for_date = $count_hash->{ $count_time };

        say STDERR ( Dumper( $count_hash_for_date ) );

        my $count_hash_array = [ values %$count_hash_for_date ];

        say STDERR ( Dumper( $count_hash_array ) );

        my $max_count = max( map { $_->{ value } } @$count_hash_array );
        foreach my $count_hash ( @$count_hash_array )
        {
            $count_hash->{ value } = $count_hash->{ value } / $max_count * 100;
        }
    }

    say STDERR "Dumping count_hash";
    say STDERR Dumper( $count_hash );

    say STDERR "country_counts_days";
    my $country_counts_days = [ values %{ $count_hash } ];
    say STDERR Dumper( $country_counts_days );

    my $country_counts_merged = [
        sort { str2time( $a->{ time } ) cmp str2time( $b->{ publish_day } ) }
        map { values %{ $_ } } ( values %{ $count_hash } )
    ];

    # say STDERR Dumper([$country_counts_merged]);

    foreach my $country_count ( @$country_counts_merged )
    {

        #say STDERR "country count";
        #say STDERR Dumper( $country_count );
        #say STDERR Dumper( [ @$fields ] );
        my %temp = %$country_count;

        #say STDERR Dumper [ @temp{ @$fields } ];
        $csv->add_line( [ @temp{ @$fields } ] );
    }

    say STDERR "added country count rows to csv";

    my $csv_string    = $csv->string;
    my $response_body = $csv_string;
    $c->response->header( "Content-Disposition" => "attachment;filename=word_list.csv" );
    $c->response->content_type( 'text/csv' );

    $c->response->content_length( length( $response_body ) );
    $c->response->body( $response_body );

    #say STDERR Dumper( $country_counts );
    return;
}

# get the url of a chart image for the given tag counts
sub _get_tag_count_map_url
{
    my ( $self, $country_code_count, $title ) = @_;

    if ( !defined( $country_code_count ) || !scalar( %{ $country_code_count } ) )
    {
        return;
    }

    my $max_tag_count = max( values %{ $country_code_count } );

    #prevent divide by zero error
    if ( $max_tag_count == 0 )
    {
        $max_tag_count = 1;
    }

    my $data =
      join( ',', map { int( ( $country_code_count->{ $_ } / $max_tag_count ) * 100 ) } sort keys %{ $country_code_count } );

    say STDERR "date: $data";

    my $countrycodes = join( '', sort keys %{ $country_code_count } );

    say STDERR "country_codes: $countrycodes";

    my $esc_title = uri_escape( $title );

    my $url_object = URI->new( 'HTTP://chart.apis.google.com/chart' );

    $url_object->query_form(
        cht  => 't',
        chtm => 'world',
        chs  => '440x220',
        chd  => "t:$data",
        chtt => $title,
        chco => 'ffffff,edf0d4,13390a',
        chld => $countrycodes,
        chf  => 'bg,s,EAF7FE'
    );

    #print Dumper($tag_counts);
    #print Dumper($country_code_count);

    return $url_object->canonical;
}

sub _country_counts_to_csv_array
{
    my ( $self, $country_counts ) = @_;

    my $country_code_3_counts =
      { map { uc( country_code2code( $_, LOCALE_CODE_ALPHA_2, LOCALE_CODE_ALPHA_3 ) ) => $country_counts->{ $_ } }
          ( sort keys %{ $country_counts } ) };

    my $country_count_csv_array = [
        map { join ',', @$_ } (
            map { [ $_, sprintf( "%10.9f", round( $country_code_3_counts->{ $_ }, 8 ) ) ] }
              sort keys %{ $country_code_3_counts }
        )
    ];

    return $country_count_csv_array;
}

# query the dashboard form data (media sets, media, and topics) and put it in
# the stash for later inclusion in the formfu fields
sub _process_and_stash_dashboard_data
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
          "  order by ms.name",
        $dashboard->{ dashboards_id }
    )->hashes;

    my $dashboard_topics = $c->dbis->query( "select * from dashboard_topics where dashboards_id = ? order by name asc",
        $dashboard->{ dashboards_id } )->hashes;

    MediaWords::Util::Tags::assign_tag_names( $c->dbis, $collection_media_sets );

    my $dashboard_dates = $self->_get_dashboard_dates( $c, $dashboard );

    my $term = $c->req->param( 'term' );

    $c->stash->{ word_cloud_term }       = $term;
    $c->stash->{ dashboard }             = $dashboard;
    $c->stash->{ media }                 = $media;
    $c->stash->{ collection_media_sets } = $collection_media_sets;
    $c->stash->{ dashboard_topics }      = $dashboard_topics;
    $c->stash->{ dashboard_dates }       = $dashboard_dates;
    $c->stash->{ compare_media_sets_id } = $c->req->param( 'compare_media_sets_id' );
}

# set the default values for the query form according to the stashed queries
sub _set_query_form_defaults
{
    my ( $self, $c, $form ) = @_;

    if ( my $queries = $c->stash->{ queries } )
    {
        for ( my $i = 0 ; $i < @{ $queries } ; $i++ )
        {
            my $q = $queries->[ $i ];
            $form->get_field( 'date' .                ( $i + 1 ) )->default( $q->{ start_date } );
            $form->get_field( 'dashboard_topics_id' . ( $i + 1 ) )->default( $q->{ dashboard_topics_ids } );
            my $media_set = $q->{ media_sets }->[ 0 ];
            if ( $media_set->{ set_type } eq 'medium' )
            {
                $form->get_field( 'medium_name' . ( $i + 1 ) )->default( $media_set->{ name } );
            }
            else
            {
                $form->get_field( 'media_sets_id' . ( $i + 1 ) )->default( $media_set->{ media_sets_id } );
            }
        }
    }
}

# create the query form, set the options of the various elements from the stash values,
# and set the default values according to the stashed queries
sub _update_query_form
{
    my ( $self, $c ) = @_;

    my $form = $self->form;
    $form->load_config_file( $c->path_to . '/root/forms/dashboard/view.yml' );
    $form->process;
    $c->stash->{ form } = $form;

    #purge labels from the form
    foreach my $element ( @{ $form->get_all_elements() } )
    {
        eval { $element->label( undef ); };
    }

    my $date1_param = $form->param_value( 'date1' );

    my $dashboard_dates = $c->stash->{ dashboard_dates };

    my $date_options = [ map { [ $_, $_ ] } @$dashboard_dates ];
    my $date1_elem = $form->get_field( { name => 'date1' } );
    $date1_elem->options( $date_options );

    if ( my $date2_elem = $form->get_field( { name => 'date2' } ) )
    {
        $date2_elem->options( $date_options );
    }

    my $dashboard_topics_id1 = $form->get_field( { name => 'dashboard_topics_id1' } );
    my $dashboard_topics_id2 = $form->get_field( { name => 'dashboard_topics_id2' } );

    my $dashboard_topics = $c->stash->{ dashboard_topics };

    my $dashboard_topics_options = [
        ( { label => 'all' } ),
        map { { label => lc( $_->{ name } ), value => $_->{ dashboard_topics_id } } } @$dashboard_topics
    ];
    $dashboard_topics_id1->options( $dashboard_topics_options );
    $dashboard_topics_id2->options( $dashboard_topics_options ) if ( $dashboard_topics_id2 );

    my $collection_media_sets = $c->stash->{ collection_media_sets };

    my $media_sets_id_options = [
        { label => '(none)', value => undef },
        map { { label => $_->{ name }, value => $_->{ media_sets_id } } } @$collection_media_sets
    ];

    $form->get_field( { name => 'media_sets_id1' } )->options( $media_sets_id_options );
    if ( my $f = $form->get_field( { name => 'media_sets_id2' } ) )
    {
        $f->options( $media_sets_id_options );
    }

    $self->_set_query_form_defaults( $c, $form );
}

# use MediaWords::Util::WordCloud to generate a word cloud with the dashboard sentences base url
sub _get_word_cloud
{
    my ( $self, $c, $dashboard, $words, $query ) = @_;

    my $base_url = "";

    my $word_cloud = MediaWords::Util::WordCloud::get_word_cloud( $c, $base_url, $words, $query );

    return $word_cloud;
}

# redirect the current page to a url that replaces the form parameters with a single queries_id param
sub _redirect_to_query_url
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $params = {};

    my $query_1 = MediaWords::DBI::Queries::find_or_create_query_by_request( $c->dbis, $c->req, 1 );
    $params->{ q1 } = $query_1->{ queries_id };

    if ( $c->req->param( 'medium_name2' ) || $c->req->param( 'media_sets_id2' ) )
    {
        my $query_2 = MediaWords::DBI::Queries::find_or_create_query_by_request( $c->dbis, $c->req, 2 );
        $params->{ q2 } = $query_2->{ queries_id };
    }

    $c->res->redirect( $c->uri_for( '/dashboard/view/' . $dashboards_id, $params ) );
}

# generate main dashboard page for a single query
sub _show_dashboard_results_single_query
{
    my ( $self, $c, $dashboard ) = @_;

    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $c->req->param( 'q1' ) );

    my $media_set_names = MediaWords::DBI::Queries::get_media_set_names( $c->dbis, $query );

    $c->stash->{ media_set_names } = join ", ", @{ $media_set_names };
    $c->stash->{ time_range } = MediaWords::DBI::Queries::get_time_range( $c->dbis, $query );
    $c->stash->{ areas_of_coverage } = MediaWords::DBI::Queries::get_dashboard_topic_names( $c->dbis, $query );

    $c->stash->{ queries }     = [ $query ];
    $c->stash->{ queries_ids } = [ $query->{ queries_id } ];

    my $words = MediaWords::DBI::Queries::get_top_500_weekly_words( $c->dbis, $query );

    my $word_cloud = $self->_get_word_cloud( $c, $dashboard, $words, $query );

    $c->stash->{ word_cloud } = $word_cloud;

}

sub _concat_or_replace
{
    my ( $old_string, $new_string, $join_text ) = @_;

    if ( !defined( $old_string ) )
    {
        return $new_string;
    }
    elsif ( $old_string eq $new_string )
    {
        return $old_string;
    }
    else
    {
        return $old_string . $join_text . $new_string;
    }
}

# generate main dashboard page for a comparison of two queries
sub _show_dashboard_results_compare_queries
{
    my ( $self, $c, $dashboard ) = @_;

    my ( $queries, $words );

    for my $i ( 0, 1 )
    {
        $queries->[ $i ] = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $c->req->param( 'q' . ( $i + 1 ) ) );

        my $query = $queries->[ $i ];

        $words->[ $i ] = MediaWords::DBI::Queries::get_top_500_weekly_words( $c->dbis, $query );

        my $media_set_names = MediaWords::DBI::Queries::get_media_set_names( $c->dbis, $query );

        my $media_set_names_text = join ", ", @{ $media_set_names };
        $c->stash->{ media_set_names } =
          _concat_or_replace( $c->stash->{ media_set_names }, $media_set_names_text, ' vs. ' );
        $c->stash->{ time_range } = _concat_or_replace(
            $c->stash->{ time_range },
            MediaWords::DBI::Queries::get_time_range( $c->dbis, $query ),
            ' vs. '
        );
        $c->stash->{ areas_of_coverage } = _concat_or_replace(
            $c->stash->{ areas_of_coverage },
            MediaWords::DBI::Queries::get_dashboard_topic_names( $c->dbis, $query ),
            ' vs. '
        );
    }

    my $word_cloud =
      MediaWords::Util::WordCloud::get_multi_set_word_cloud( $c, "/dashboard/sentences/$dashboard->{ dashboards_id }",
        $words, $queries );

    MediaWords::Util::WordCloud::add_query_labels( $c->dbis, $queries->[ 0 ], $queries->[ 1 ] );

    MediaWords::DBI::Queries::add_cos_similarities( $c->dbis, $queries );

    $c->stash->{ word_cloud }  = $word_cloud;
    $c->stash->{ queries }     = $queries;
    $c->stash->{ queries_ids } = [ map { $_->{ queries_id } } @{ $queries } ];
}

# generate main dashboard page
sub _show_dashboard_results
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    if ( $c->req->param( 'q2' ) )
    {
        $self->_show_dashboard_results_compare_queries( $c, $dashboard );
    }
    else
    {
        $self->_show_dashboard_results_single_query( $c, $dashboard );
    }
}

# generate main dashboard page
sub view : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    if ( scalar( keys %{ $c->req->parameters() } ) == 0 )
    {
        if ( !defined( $dashboards_id ) )
        {
            $dashboards_id = $self->_default_dashboards_id( $c );
        }

        $self->_redirect_to_default_page( $c, $dashboards_id );

        return;
    }

    if ( !$c->req->param( 'q1' ) )
    {
        $self->_redirect_to_query_url( $c, $dashboards_id );
        return;
    }

    $self->_process_and_stash_dashboard_data( $c, $dashboards_id );

    $self->_show_dashboard_results( $c, $dashboards_id );

    $self->_update_query_form( $c );

    if ( $c->req->param( 'cmaponly') ) 
    {
       $c->stash->{ template } = 'zoe_website_template/coverage_map_only.tt2';
    }
    elsif ( $c->req->param( 'wconly') ) 
    {
       $c->stash->{ template } = 'zoe_website_template/word_cloud_only.tt2';
    }
    else
    {
       $c->stash->{ template } = 'zoe_website_template/media_cloud_rough_html.tt2';
    }
}

# static news page
sub news : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    if ( !defined( $dashboards_id ) )
    {
        $dashboards_id = $self->_default_dashboards_id( $c );
    }
    $c->stash->{ dashboard } = $self->_get_dashboard( $c, $dashboards_id );
    $c->stash->{ template } = 'zoe_website_template/news.tt2';
}

# static about page
sub about : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    if ( !defined( $dashboards_id ) )
    {
        $dashboards_id = $self->_default_dashboards_id( $c );
    }
    $c->stash->{ dashboard } = $self->_get_dashboard( $c, $dashboards_id );
    $c->stash->{ template } = 'zoe_website_template/about.tt2';
}

# static faq page
sub faq : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    if ( !defined( $dashboards_id ) )
    {
        $dashboards_id = $self->_default_dashboards_id( $c );
    }
    $c->stash->{ dashboard } = $self->_get_dashboard( $c, $dashboards_id );
    $c->stash->{ template } = 'zoe_website_template/faq.tt2';
}

# base dir
my $_base_dir    = __DIR__ . '/../../..';
my $web_root_dir = "$_base_dir/root";
Readonly my $dump_dir => "$web_root_dir/include/data_dumps";

sub get_data_dump_file_list
{

    opendir( DIR, $dump_dir ) || die;
    my @files = readdir( DIR );
    closedir( DIR );

    my $data_dump_files = [ grep { /^media_word_story_((full)|(incremental))_dump_.*zip/ } @files ];

    return $data_dump_files;
}

sub _dump_file_size
{
    my ( $dump_file_name ) = @_;

    my $filesize = stat( "$dump_dir/$dump_file_name" )->size;

    return $filesize;
}

sub _bytes_to_human_readable
{
    my ( $bytes ) = @_;

    my $kb = $bytes / 1024.0;

    if ( $kb < 1 )
    {
        return "$bytes B";
    }

    my $mb = $kb / 1024.0;

    if ( $mb < 1 )
    {
        $kb = int( ( $kb + 0.05 ) * 10 ) / 10;
        return "$kb KB";
    }

    my $gb = $mb / 1024.0;

    if ( $gb < 1 )
    {
        $mb = int( ( $mb + 0.05 ) * 10 ) / 10;
        return "$mb MB";
    }

    $gb = int( ( $gb + 0.05 ) * 10 ) / 10;

    return "$gb GB";
}

sub _get_dump_file_info
{
    my ( $dump_file_name ) = @_;

    my $ret = {};

    $ret->{ size_bytes } = _dump_file_size( $dump_file_name );

    $ret->{ size_human } = _bytes_to_human_readable( $ret->{ size_bytes } );

    $dump_file_name =~ s/media_word_story_.*dump_(.*)\.zip/$1/;
    my $unique_name_info = $1;

    $unique_name_info =~ /(...)_(...)_(.\d)_(\d\d:\d\d:\d\d)_(\d\d\d\d)_(\d+)_(\d+)/;

    my $wday          = $1;
    my $month         = $2;
    my $mday          = $3;
    my $time          = $4;
    my $year          = $5;
    my $stories_start = $6;
    my $stories_end   = $7;

    $mday =~ s/_//;

    $ret->{ wday }  = $wday;
    $ret->{ month } = $month;
    $ret->{ mday }  = $mday;
    $ret->{ time }  = $time;
    $ret->{ year }  = $year;

    $ret->{ stories_start } = $stories_start;
    $ret->{ stories_end }   = $stories_end;

    return $ret;
}

sub _unix_time_for_file
{
    my ( $arr ) = @_;

    my $file_info = $arr->[ 2 ];

    my $utime = str2time( "$file_info->{ mday } $file_info->{ month } $file_info->{ ret }  $file_info->{ time } " );
}

sub data_dumps : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    if ( !defined( $dashboards_id ) )
    {
        $dashboards_id = $self->_default_dashboards_id( $c );
    }

    $c->stash->{ dashboard } = $self->_get_dashboard( $c, $dashboards_id );

    my $data_dump_files = get_data_dump_file_list();

    my $data_dumps = [
        map {
            my $file_date = $_;
            $file_date =~ s/media_word_story_.*dump_(.*)\.zip/$1/;
            [ $_, $file_date, _get_dump_file_info( $_ ) ]
          } @$data_dump_files
    ];

    $data_dumps = [ sort { _unix_time_for_file( $a ) <=> _unix_time_for_file( $b ) } @{ $data_dumps } ];

    my $full_data_dumps        = [ grep { $_->[ 0 ] =~ /.*_full_.*/ } @$data_dumps ];
    my $incremental_data_dumps = [ grep { $_->[ 0 ] =~ /.*_incremental_.*/ } @$data_dumps ];

    say STDERR Dumper( $data_dump_files );
    say STDERR Dumper( $data_dumps );

    $c->stash->{ dump_dir } = "$web_root_dir/include/data_dumps";

    $c->stash->{ data_dumps } = $data_dumps;

    $c->stash->{ full_data_dumps }        = $full_data_dumps;
    $c->stash->{ incremental_data_dumps } = $incremental_data_dumps;

    $c->stash->{ template } = 'zoe_website_template/data_dumps.tt2';
}

sub coverage_changes : Local : FormConfig
{
    my ( $self, $c, $dashboards_id ) = @_;

    $self->_process_and_stash_dashboard_data( $c, $dashboards_id );

    $self->_update_query_form( $c );

    if ( $c->req->param( 'show_results' ) )
    {
        $c->stash->{ show_results }          = 1;
        $c->stash->{ compare_media_sets_id } = $c->req->param( 'compare_media_sets_id' );
    }
    $c->stash->{ template } = 'zoe_website_template/coverage_changes.tt2';
}

sub json_popular_queries : Local
{
    my ( $self, $c ) = @_;

    my $popular_queries = $c->dbis->query( "select * from popular_queries order by count desc limit 5 " )->hashes;

    foreach my $popular_query ( @$popular_queries )
    {
        my $query_params = { q1 => $popular_query->{ queries_id_0 } };

        if ( defined( $popular_query->{ queries_id_1 } ) )
        {
            $query_params->{ q2 } = $popular_query->{ queries_id_1 };
        }

        $popular_query->{ url } = $c->uri_for( '/dashboard' . $popular_query->{ dashboard_action }, $query_params ) . '';
    }

    #say STDERR Dumper( $popular_queries);

    $c->res->body( encode_json( $popular_queries ) );

    return;
}

sub json_author_search : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $term = $c->req->param( 'term' ) || 0;

    $term = $term . '%';

    my $terms =
      $c->dbis->query( "select authors_id, author_name as label from authors where author_name like lower(?) OR " .
          "  lower(split_part(author_name, ' ', 1)) like lower(?)   OR       " .
          "  lower(split_part(author_name, ' ', 2)) like lower(?)   OR       " .
          "  lower(split_part(author_name, ' ', 3)) like lower(?)    LIMIT 100     ",
        $term, $term, $term, $term )->hashes;

    #print encode_json($terms);

    $c->res->body( encode_json( $terms ) );

    return;
}

sub author_query : Local : FormConfig
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $form = $c->stash->{ form };

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $dashboard_dates = $self->_get_dashboard_dates( $c, $dashboard );
    $form->get_field( { name => 'date1' } )->options( [ map { [ $_, $_ ] } @$dashboard_dates ] );

    my $show_results = $c->req->param( 'show_results' ) || 0;

    if ( $form->submitted() )
    {
        my $date = $self->get_start_of_week( $c, $c->req->param( 'date1' ) );

        my $dashboard_topic = $c->dbis->find_by_id( 'dashboard_topics', $c->req->param( 'dashboard_topics_id1' ) );

        my $authors_id1 = $c->req->param( 'authors_id1' ) || die "no authors_id1";

        my $words = $self->_get_author_words( $c, 1, $authors_id1 );

        if ( scalar( @{ $words } ) == 0 )
        {
            $c->stash->{ error_message } = "No words found for this author and date";
        }
        else
        {
            my $word_cloud = $self->_get_word_cloud( $c, $dashboard, $words, { authors_id => $authors_id1 } );

            $c->stash->{ show_results } = 1;
            $c->stash->{ word_cloud }   = $word_cloud;
        }
    }
    elsif ( $form->has_errors() )
    {
        $c->stash->{ error_message } = "Form has errors: \n " . Dumper( [ $form->get_errors() ] );
    }

    $c->stash->{ dashboard }       = $dashboard;
    $c->stash->{ dashboard_dates } = $dashboard_dates;
    $c->stash->{ template }        = 'zoe_website_template/author_query.tt2';
}

sub _translate_word_list
{
    my ( $self, $c, $words ) = @_;

    require MediaWords::Util::Translate;
    import MediaWords::Util::Translate;

    my $ret = [];

    for my $word ( @{ $words } )
    {
        my $translated_word = { %{ $word } };
        $translated_word->{ term } = MediaWords::Util::Translate::translate( $translated_word->{ term } );

        push @{ $ret }, $translated_word;
    }

    return $ret;
}

# get start of week for the given date from postgres
sub get_start_of_week
{
    my ( $self, $c, $date ) = @_;

    $date || die( 'no date' );

    my ( $start_date ) = $c->dbis->query( "select date_trunc( 'week', ?::date )", $date )->flat;

    return substr( $start_date, 0, 10 );
}

# get the media_set from one of the following cgi params:
# media_sets_id, media_id, medium_name, media_clusters_id
sub get_media_set_from_params
{
    my ( $self, $c, $media_set_num ) = @_;

    #TODO refactor when we got 5.8 support
    $media_set_num = defined( $media_set_num ) ? $media_set_num : '';

    my $media_set;

    if ( my $media_sets_id = $c->req->param( 'media_sets_id' . $media_set_num ) )
    {
        return $c->dbis->find_by_id( 'media_sets', $media_sets_id )
          || die( "no media_set for media_sets_id '$media_sets_id'" );
    }
    elsif ( my $media_id = $c->req->param( 'media_id' . $media_set_num ) )
    {
        return $c->dbis->query( "select * from media_sets where media_id = ?", $media_id )->hash
          || die( "no media_set for media_id '$media_id'" );
    }
    elsif ( my $medium_name = $c->req->param( 'medium_name' . $media_set_num ) )
    {
        return $c->dbis->query(
            "select ms.* from media_sets ms, media m " . "  where ms.media_id = m.media_id and m.name = ?", $medium_name )
          ->hash
          || die( "no media_set for medium_name '$medium_name'" );
    }
    elsif ( my $media_clusters_id = $c->req->param( 'media_clusters_id' . $media_set_num ) )
    {
        return $c->dbis->query( "select * from media_sets where media_clusters_id = ?", $media_clusters_id )->hash
          || die( "no media_set for media_clusters_id '$media_clusters_id'" );
    }
    else
    {
        say STDERR Dumper( $c->req );
        die( "no media_set id for '$media_set_num'" );
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

# die if the dashboard topic is not valid for the given date
sub validate_dashboard_topic_date
{
    my ( $self, $c, $dashboard_topic, $date ) = @_;

    my $val_result = $self->_invalid_dashboard_topic_date( $c, $dashboard_topic, $date );

    die $val_result if $val_result;
}

# die if the dashboard topic is not valid for the given date
sub _invalid_dashboard_topic_date
{
    my ( $self, $c, $dashboard_topic, $date ) = @_;

    if ( !$dashboard_topic )
    {
        return;
    }

    $date .= " 00:00:00";

    if ( $date lt $dashboard_topic->{ start_date } )
    {
        return "date '$date' is before topic start date $dashboard_topic->{ start_date }";
    }

    if ( $date gt $dashboard_topic->{ end_date } )
    {
        return "date '$date' is after topic end date $dashboard_topic->{ end_date }";
    }

    return;
}

sub print_time
{
    my ( $s ) = @_;

    return;

    my $t = Time::HiRes::gettimeofday();
    $_start_time ||= $t;
    $_last_time  ||= $t;

    my $elapsed     = $t - $_start_time;
    my $incremental = $t - $_last_time;

    printf( STDERR "time $s: %f elapsed %f incremental\n", $elapsed, $incremental );

    $_last_time = $t;
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

# list the sentences matching the given stem for the given author
sub sentences_author : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    require MediaWords::Util::Translate;
    import MediaWords::Util::Translate;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $authors_id = $c->req->param( 'authors_id' ) || die( 'no authors_id' );
    my $stem       = $c->req->param( 'stem' )       || die( 'no stem' );
    my $term       = $c->req->param( 'term' )       || die( 'no term' );

    $authors_id += 0;
    my $author = $c->dbis->find_by_id( 'authors', $authors_id ) || die( "can't find author $authors_id" );

    my $quoted_stem = $c->dbis->dbh->quote( $stem );

    my $sentences =
      $c->dbis->query( "select distinct ss.* " .
          "  from story_sentences ss, story_sentence_words ssw, stories s, authors_stories_map asm " .
          "  where ss.stories_id = ssw.stories_id and ss.sentence_number = ssw.sentence_number " .
          "    and s.stories_id = ssw.stories_id and ssw.stories_id = asm.stories_id " .
          "    and asm.authors_id = $authors_id and ssw.stem = $quoted_stem " .
          "  order by ss.publish_date, ss.stories_id, ss.sentence asc " . "  limit 500" )->hashes;

    my $stories_ids_hash;
    map { $stories_ids_hash->{ $_->{ stories_id } } = 1 } @{ $sentences };
    my $stories_ids_list = MediaWords::Util::SQL::get_ids_in_list( [ keys( %{ $stories_ids_hash } ) ] );

    my $stories =
      $c->dbis->query( "select * from stories where stories_id in ( $stories_ids_list ) order by publish_date" )->hashes;

    my $stories_hash;
    map { $stories_hash->{ $_->{ stories_id } } = $_ } @{ $stories };
    map { push( @{ $stories_hash->{ $_->{ stories_id } }->{ sentences } }, $_ ) } @{ $sentences };

    #my $page_description =

    $c->stash->{ dashboard }       = $dashboard;
    $c->stash->{ term }            = $term;
    $c->stash->{ translated_term } = MediaWords::Util::Translate::translate( $term );
    $c->stash->{ params }          = $c->req->params;
    $c->stash->{ template }        = 'dashboard/sentences_author.tt2';
    $c->stash->{ stories }         = $stories;
    $c->stash->{ author }          = $author;
}

# list the sentences matching the given stem for the given medium within the given query
sub sentences_medium : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $media_id = $c->req->param( 'media_id' ) || die( 'no media_id' );
    my $stem     = $c->req->param( 'stem' )     || die( 'no stem' );
    my $term     = $c->req->param( 'term' )     || die( 'no term' );

    my $queries_ids = [ $c->req->param( 'queries_ids' ) ];

    $queries_ids = ( !$queries_ids || ref( $queries_ids ) ) ? $queries_ids : [ $queries_ids ];

    my $translate = $self->_set_translate_state( $c );

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    $medium->{ stem_percentage } = $c->req->param( 'stem_percentage' );

    my $queries = [ map { MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $_ ) } @{ $queries_ids } ];

    my $stories = MediaWords::DBI::Queries::get_medium_stem_stories_with_sentences( $c->dbis, $stem, $medium, $queries );

    my $queries_description = join( " or ", map { $_->{ description } } @{ $queries } );

    $c->keep_flash( ( 'translate' ) );

    $c->stash->{ dashboard }           = $dashboard;
    $c->stash->{ term }                = $term;
    $c->stash->{ translated_term }     = MediaWords::Util::Translate::translate( $term );
    $c->stash->{ medium }              = $medium;
    $c->stash->{ params }              = $c->req->params;
    $c->stash->{ template }            = 'dashboard/sentences_medium.tt2';
    $c->stash->{ stories }             = $stories;
    $c->stash->{ queries_description } = $queries_description;
}

sub sentences_medium_json : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $media_id = $c->req->param( 'media_id' ) || die( 'no media_id' );
    my $stem     = $c->req->param( 'stem' )     || die( 'no stem' );

    my $queries_ids = [ $c->req->param( 'queries_ids' ) ];

    $queries_ids = ( !$queries_ids || ref( $queries_ids ) ) ? $queries_ids : [ $queries_ids ];

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    $medium->{ stem_percentage } = $c->req->param( 'stem_percentage' );

    my $queries = [ map { MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $_ ) } @{ $queries_ids } ];

    my $stories = MediaWords::DBI::Queries::get_medium_stem_stories_with_sentences( $c->dbis, $stem, $medium, $queries );

    return $c->res->body( encode_json( $stories ) );
}

sub page_count_increment : Local
{
    my ( $self, $c ) = @_;

    # my $url                 = $c->req->body_params->{ url };
    # my $query_description_0 = $c->req->body_params->{ query_0_description };
    # my $query_description_1 = $c->req->body_params->{ query_1_description };

    my $dashboard_action    = $c->req->param( 'action' );
    my $url_params          = $c->req->param( 'url_params' );
    my $query_description_0 = $c->req->param( 'query_0_description' );
    my $query_description_1 = $c->req->param( 'query_1_description' );

    my $queries_id_0 = $c->req->param( 'queries_id_0' );
    my $queries_id_1 = $c->req->param( 'queries_id_1' );

    if ( !$queries_id_1 )
    {
        undef( $queries_id_1 );
    }

    #say STDERR Dumper( $c->req->body_params );
    #say STDERR "query_0  $query_description_0 query_1  $query_description_1";

    my $popular_query;

    if ( $queries_id_1 )
    {
        $popular_query = $c->dbis->query( 'SELECT * from popular_queries where queries_id_0 = ? and queries_id_1 = ?',
            $queries_id_0, $queries_id_1 )->hash;

    }
    else
    {
        $popular_query =
          $c->dbis->query( 'SELECT * from popular_queries where queries_id_0 = ? and queries_id_1 is null', $queries_id_0 )
          ->hash;
    }

    if ( !$popular_query )
    {
        $popular_query = $c->dbis->query(
"INSERT INTO popular_queries ( dashboard_action, url_params, query_0_description, query_1_description, queries_id_0, queries_id_1) VALUES ( ?, ?, ?, ?, ?, ?) RETURNING *",
            $dashboard_action, $url_params, $query_description_0, $query_description_1, $queries_id_0, $queries_id_1 )->hash;

    }

    $popular_query->{ count }++;

    die Dumper( $popular_query ) if !$popular_query->{ popular_queries_id };

    $c->dbis->update_by_id( 'popular_queries', $popular_query->{ popular_queries_id }, $popular_query );
    return $c->res->body( ' ' );
}

sub coverage_map_iframe : Local
{
    my ( $self, $c ) = @_;

    my $csv_url = $c->req->param( 'url' );
    my $height  = $c->req->param( 'height' );
    my $width   = $c->req->param( 'width' );

    if ( $height )
    {
        $c->stash->{ height } = int( $height );
    }

    if ( $width )
    {
        $c->stash->{ width } = int( $width );
    }

    $c->stash->{ csv_url }  = $csv_url;
    $c->stash->{ template } = 'zoe_website_template/coverage_map_iframe.tt2';
}

# list the sentence counts for each medium in the query for the given stem
sub sentences : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    if ( $c->req->param( 'authors_id' ) )
    {
        return $self->sentences_author( $c, $dashboards_id );
    }

    my $iframe = 0;
    if ( $c->req->param( 'iframe' ) )
    {
        $iframe = 1;
    }

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $stem = $c->req->param( 'stem' ) || die( 'no stem' );
    my $term = $c->req->param( 'term' ) || die( 'no term' );

    my $queries = [ map { MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $_ ) } $c->req->param( 'queries_ids' ) ];
    my $queries_description = join( " or ", map { $_->{ description } } @{ $queries } );
    my $media = MediaWords::DBI::Queries::get_media_matching_stems( $c->dbis, $stem, $queries );

    $c->stash->{ dashboard }           = $dashboard;
    $c->stash->{ stem }                = $stem;
    $c->stash->{ term }                = $term;
    $c->stash->{ queries_description } = $queries_description;
    $c->stash->{ queries_ids }         = [ $c->req->param( 'queries_ids' ) ];
    $c->stash->{ media }               = $media;

    #$c->stash->{ template } = 'dashboard/sentences.tt2';
    $c->stash->{ template } = 'dashboard/sentences_iframe.tt2';

}

# given a list of terms, return a quoted, comma-separated list of stems
sub get_stems_in_list
{
    my ( $self, $c, $term_list ) = @_;

    $term_list =~ s/[^\w ]//g;

    my $terms = [ split( ' ', $term_list ) ];

    my $stemmer = MediaWords::Util::Stemmer->new;

    my $stems = $stemmer->stem( @{ $terms } );

    my $stems_in_list = join( ',', map { "'$_'" } @{ $stems } );

    return $stems_in_list;
}

# accept a dashboard id, a set of terms, and a date range and return a csv of the frequency with which each term
# appears for the media_set / date.  Include both the collection media_sets in aggregate and each individual media source
sub compare_media_set_terms : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $c->dbis->find_by_id( 'dashboards', $dashboards_id )
      || die( "dashboard not found: $dashboards_id" );

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/compare_media_set_terms.yml',
            method           => 'post',
            action           => $c->uri_for( "/dashboard/compare_media_set_terms/$dashboards_id" ),
        }
    );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ dashboard } = $dashboard;
        $c->stash->{ form }      = $form;
        $c->stash->{ template }  = 'dashboard/compare_media_set_terms.tt2';
        return;
    }

    my $start_date = $c->req->param( 'start_date' ) || die( "no start_date" );
    my $end_date   = $c->req->param( 'end_date' )   || die( "no end_date" );
    my $term_list  = $c->req->param( 'term_list' )  || die( "no term_list" );

    if ( $start_date !~ /\d\d\d\d-\d\d-\d\d/ )
    {
        die( "start_date is not in YYYY-MM-DD format" );
    }

    if ( $end_date !~ /\d\d\d\d-\d\d-\d\d/ )
    {
        die( "start_date is not in YYYY-MM-DD format" );
    }

    my $stems_in_list = $self->get_stems_in_list( $c, $term_list );

    my $collection_term_counts =
      $c->dbis->query( "select ms.name, ms.set_type, publish_day, stem_count, stem, term " .
          "  from daily_words dw, media_sets ms, dashboard_media_sets dms " .
          "  where dw.media_sets_id = ms.media_sets_id and dms.dashboards_id = $dashboards_id and " .
          "    dms.media_sets_id = ms.media_sets_id and " .
          "    dw.publish_day >= '$start_date'::date and dw.publish_day <= '$end_date'::date and " .
          "    dw.stem in ( $stems_in_list )and dw.dashboard_topics_id is null " .
          "  order by ms.set_type, ms.name, publish_day, stem" )->hashes;

    my $media_term_counts =
      $c->dbis->query( "select ms.name, ms.set_type, publish_day, stem_count, stem, term " .
          "  from daily_words dw, media_sets ms, dashboard_media_sets dms, media_sets_media_map msmm " .
          "  where dw.media_sets_id = ms.media_sets_id and dms.dashboards_id = $dashboards_id and " .
          "    dms.media_sets_id = msmm.media_sets_id and msmm.media_id = ms.media_id and " .
          "    dw.publish_day >= '$start_date'::date and dw.publish_day <= '$end_date'::date and " .
          "    dw.stem in ( $stems_in_list ) and dw.dashboard_topics_id is null " .
          "  order by ms.set_type, ms.name, publish_day, stem" )->hashes;

    my $csv = Text::CSV_XS->new;
    my $output;

    $csv->combine( qw/media_set_name media_set_type publish_day stem_count stem term/ );
    $output .= $csv->string . "\n";

    for my $term_count ( @{ $collection_term_counts }, @{ $media_term_counts } )
    {
        $csv->combine( map { $term_count->{ $_ } } qw/name set_type publish_day stem_count stem term/ );

        $output .= $csv->string . "\n";
    }

    $c->res->header( 'Content-Disposition', qq[attachment; filename="term_counts.csv"] );
    $c->res->content_type( 'text/csv' );
    $c->res->body( $output );
}

# send an email reporting buggy behavior including the url of the reported page
sub report_bug : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $c->dbis->find_by_id( 'dashboards', $dashboards_id )
      || die( "dashboard not found: $dashboards_id" );
    my $url = $c->req->param( 'url' ) || die( 'no url' );

    if ( !$c->req->param( 'submit' ) )
    {
        $c->stash->{ dashboard } = $dashboard;
        $c->stash->{ url }       = $url;
        $c->stash->{ template }  = 'dashboard/report_bug.tt2';
        return;
    }

    my $config      = MediaWords::Util::Config::get_config;
    my $smtp_server = $config->{ mail }->{ smtp_server } || die( 'no mail:smtp_server in mediawords.yml' );
    my $bug_email   = $config->{ mail }->{ bug_email } || die( 'no mail:bug_email in mediawords.yml' );

    my $email = $c->req->param( 'email' ) || $bug_email;
    my $description = $c->req->param( 'description' );

    my $smtp = Net::SMTP->new( $smtp_server ) || die;

    $smtp->mail( $email )   || die;
    $smtp->to( $bug_email ) || die;

    $smtp->data()                                                                          || die;
    $smtp->datasend( "To: $bug_email\nFrom: $email\nSubject: Media Cloud Bug Report\n\n" ) || die;
    $smtp->datasend( "Url: $url\n\nDescription: $description\n\n" )                        || die;
    $smtp->dataend()                                                                       || die;

    $smtp->quit || die;

    my $redirect =
      $c->uri_for( '/dashboard/list/' . $dashboard->{ dashboards_id }, { status_msg => 'Bug report filed.  Thanks!' } );
    $c->res->redirect( $redirect );
}

# list and describe all media sets in the current dashboard
sub media_sets : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $media_sets = $c->dbis->query(
        "select ms.* from media_sets ms, dashboard_media_sets dms " . "  where ms.media_sets_id = dms.media_sets_id " .
          "    and dashboards_id = $dashboard->{ dashboards_id } " . "    and ms.set_type = 'collection' " .
          "  order by ms.name " )->hashes;

    $c->stash->{ dashboard }  = $dashboard;
    $c->stash->{ media_sets } = $media_sets;
    $c->stash->{ template }   = 'zoe_website_template/media_sets.tt2';
}

sub media : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    my $dashboard = $self->_get_dashboard( $c, $dashboards_id );

    my $media_sets_id = $c->req->param( 'media_sets_id' ) || die( 'no media_sets_id' );
    my $media_set = $c->dbis->query(
        "select ms.* from media_sets ms, dashboard_media_sets dms " . "  where ms.media_sets_id = dms.media_sets_id " .
          "    and dashboards_id = $dashboard->{ dashboards_id } " . "    and ms.set_type = 'collection' " .
          "    and ms.media_sets_id = ?",
        $media_sets_id
      )->hash
      || die( 'media_set $media_sets_id not found' );

    my $media =
      $c->dbis->query( "select * from media m, media_sets_media_map msmm " .
          "  where m.media_id = msmm.media_id and msmm.media_sets_id = $media_set->{ media_sets_id } " .
          "  order by name " )->hashes;

    $c->stash->{ dashboard } = $dashboard;
    $c->stash->{ media_set } = $media_set;
    $c->stash->{ media }     = $media;
    $c->stash->{ template }  = 'zoe_website_template/media.tt2';
}

1;
