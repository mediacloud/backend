package MediaWords::Controller::Admin::Stop_Server;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

#use parent 'Catalyst::Controller';
use parent 'Catalyst::Controller::HTML::FormFu';

use HTML::TagCloud;
use List::Util;
use Number::Format qw(:subs);
use URI::Escape;
use List::Util qw (max min maxstr minstr reduce sum);
use List::MoreUtils qw/:all/;

use MediaWords::Controller::Admin::Visualize;
use MediaWords::Util::Chart;
use MediaWords::Util::Config;
use MediaWords::Util::Countries;

#use MediaWords::Util::Translate;

use MediaWords::Util::WordCloud;

use Data::Dumper;
use Date::Format;
use Date::Parse;
use Date::Calc qw(:all);
use JSON;
use Time::HiRes;
use XML::Simple qw(:strict);
use Dir::Self;
use Readonly;
use CHI;
use File::stat;
use Data::Google::Visualization::DataTable::MediaWords;
use Date::Parse;
use DateTime::Format::Pg;
use Time::HiRes;

# statics for state between print_time() calls
my $_start_time;
my $_last_time;

sub quit : Global { exit( 0 ) }

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    say STDERR "quitting server";

    $c->response->body( "Shutting down server\n" );
    quit();
    return;
}

1;
