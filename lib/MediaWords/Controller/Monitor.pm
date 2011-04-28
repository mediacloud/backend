package MediaWords::Controller::Monitor;

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
use CHI;
use File::stat;
use Data::Google::Visualization::DataTable;

# statics for state between print_time() calls
my $_start_time;
my $_last_time;

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    #    my $dashboards_id = $self->_default_dashboards_id( $c );

    #    $self->_redirect_to_default_page( $c, $dashboards_id );
}

sub crawler_google_data_table : Local
{
    my ( $self, $c ) = @_;

    say STDERR "crawler_google_data_table";

    my $download_day_counts = $c->dbis->query(
"select date_trunc('day', download_time) as day, count(*) from downloads where download_time > now() - interval '10 weeks' group by date_trunc('day', download_time);"
    )->hashes();

    my $datatable = Data::Google::Visualization::DataTable->new();

    $datatable->add_columns(
        { id => 'day',   label => 'Date',  type => 'string' },
        { id => 'count', label => 'Count', type => 'number' },
    );
    say STDERR Dumper( $download_day_counts );

    $datatable->add_rows( @{ $download_day_counts } );

    my $json_output = $datatable->output_json(

        #columns => ['date','number','string' ],
        # pretty  => 1,
    );

    $c->res->body( $json_output );
    $c->res->content_type( "application/json" );

    $c->stash->{ download_day_counts } = $download_day_counts;

    #$c->stash->{ template } = 'monitor/crawler_stats.tt2';
}

# generate main dashboard page
sub view : Local
{
    my ( $self, $c ) = @_;

    say STDERR "Monitor view";

    my $download_day_counts = $c->dbis->query(
"select date_trunc('day', download_time) as day, count(*) from downloads where download_time > now() - interval '10 weeks' group by date_trunc('day', download_time);"
    )->hashes();

    say STDERR Dumper( $download_day_counts );

    $c->stash->{ download_day_counts } = $download_day_counts;
    $c->stash->{ template }            = 'monitor/crawler_stats.tt2';
}

1;
