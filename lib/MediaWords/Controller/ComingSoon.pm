package MediaWords::Controller::ComingSoon;

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
use MediaWords::Controller::Dashboard;

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    $self->message( $c );
}

# static about page
sub message : Local
{
    my ( $self, $c ) = @_;

    my $dashboards_id = MediaWords::Controller::Dashboard::get_default_dashboards_id( $c->dbis );
    my $default_dashboard = MediaWords::Controller::Dashboard::get_dashboard( $c->dbis, $dashboards_id );


    my $redirect = $c->uri_for( '/dashboard/view/' );

    $c->res->redirect( $redirect );

    if (0)
    {
      $c->stash->{ dashboard } = $default_dashboard;
      $c->stash->{ template }  = 'zoe_website_template/comingsoon.tt2';
    }
}

1;
