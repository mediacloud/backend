package MediaWords::Munin;

use strict;
use warnings;

use File::Basename;
use Data::Dumper;
use Readonly;
use DBIx::Simple;
use Time::localtime;
use File::stat;

use Carp qw/croak/;

use Exporter qw( import );

# http://munin-monitoring.org/wiki/fieldname.colour
# note the difference between "COLOR" and "COLOUR"
Readonly our $COLOR0 => 'COLOUR0';
Readonly our $COLOR1 => 'COLOUR1';
Readonly our $COLOR2 => 'COLOUR2';
Readonly our $COLOR3 => 'COLOUR3';
Readonly our $COLOR4 => 'COLOUR4';
Readonly our $COLOR5 => 'COLOUR5';
Readonly our $COLOR6 => 'COLOUR6';
Readonly our $COLOR7 => 'COLOUR7';
Readonly our $COLOR8 => 'COLOUR8';
Readonly our $COLOR9 => 'COLOUR9';
Readonly our $COLOR10 => 'COLOUR10';
Readonly our $COLOR11 => 'COLOUR11';
Readonly our $COLOR12 => 'COLOUR12';
Readonly our $COLOR13 => 'COLOUR13';
Readonly our $COLOR14 => 'COLOUR14';
Readonly our $COLOR15 => 'COLOUR15';
Readonly our $COLOR16 => 'COLOUR16';
Readonly our $COLOR17 => 'COLOUR17';
Readonly our $COLOR18 => 'COLOUR18';
Readonly our $COLOR19 => 'COLOUR19';
Readonly our $COLOR20 => 'COLOUR20';
Readonly our $COLOR21 => 'COLOUR21';
Readonly our $COLOR22 => 'COLOUR22';
Readonly our $COLOR23 => 'COLOUR23';
Readonly our $COLOR24 => 'COLOUR24';
Readonly our $COLOR25 => 'COLOUR25';
Readonly our $COLOR26 => 'COLOUR26';
Readonly our $COLOR27 => 'COLOUR27';
Readonly our $COLOR28 => 'COLOUR28';

# http://munin-monitoring.org/wiki/fieldname.draw
Readonly our $LINE1 => 'LINE1';
Readonly our $LINE2 => 'LINE2';
Readonly our $LINE3 => 'LINE3';
Readonly our $STACK => 'STACK';
Readonly our $LINESTACK1 => 'LINESTACK1';
Readonly our $LINESTACK2 => 'LINESTACK2';
Readonly our $LINESTACK3 => 'LINESTACK3';
Readonly our $AREASTACK => 'AREASTACK';

our @EXPORT = qw(
    $COLOR0
    $COLOR1
    $COLOR2
    $COLOR3
    $COLOR4
    $COLOR5
    $COLOR6
    $COLOR7
    $COLOR8
    $COLOR9
    $COLOR10
    $COLOR11
    $COLOR12
    $COLOR13
    $COLOR14
    $COLOR15
    $COLOR16
    $COLOR17
    $COLOR18
    $COLOR19
    $COLOR20
    $COLOR21
    $COLOR22
    $COLOR23
    $COLOR24
    $COLOR25
    $COLOR26
    $COLOR27
    $COLOR28
    $LINE1
    $LINE2
    $LINE3
    $STACK
    $LINESTACK1
    $LINESTACK2
    $LINESTACK3
    $AREASTACK
);

sub _default_category() {
    return 'mediacloud';
}

sub _default_args() {
    return '--base 1000 -l 0';
}

sub _metric_id($) {

    my $metric = shift;

    my $plugin_script_name = basename( $0 );
    my $suffix = $metric->{ suffix } // '';
    $suffix =~ s/\./_/;

    return $plugin_script_name . ( $suffix ? '_' . $suffix : '' );
}

sub _resolve_value($) {
    my $value = shift;

    if ( defined $value ) {
        if ( ref $value eq ref sub { 'DUMMY' } ) {
            return $value->() + 0;
        } else {
            return $value + 0;
        }
    } else {
        return '';
    }
}

sub _validate_arguments($) {
    my $args = shift;

    unless ( ref $args eq ref {} ) {
        croak 'Arguments must be an hashref';
    }

    # e.g. "Pending downloads"
    $args->{ title } or croak 'You must set "graph_title"';

    # e.g. "Downloads with state = 'pending'"
    $args->{ info } or croak 'You must set "graph_info"';

    # e.g. "Downloads"
    $args->{ vlabel } or croak 'You must set "graph_vlabel"';

    # arrayref of MediaWords::Munin::Plugin::Metric objects
    $args->{ metrics } or croak 'You must set "graph_metrics"';
    unless ( ref $args->{ metrics } eq ref [] ) {
        croak '"graph_metrics" must be an arrayref';
    }

    my %unique_ids;
    foreach my $metric ( @{ $args->{ metrics } } ) {

        unless ( ref $metric eq ref {} ) {
            croak 'One of the metrics if not a hashref; metric: ' . Dumper( $metric );
        }

        # e.g. "downloads"
        $metric->{ label } or croak 'You must set "label"';

        # e.g. MediaWords::Munin::Plugin::Metric::COLOR11
        $metric->{ color } or croak 'You must set "color"';

        # e.g. a subref; must return integer
        $metric->{ value } or croak 'You must set "value"';

        # e.g. { from => 0, to => 10 }
        if ( $metric->{ warning } and ref $metric->{ warning } ne ref {} ) {
            croak "'warning' must be a hashref";
        }

        if ( $metric->{ critical } and ref $metric->{ critical } ne ref {} ) {
            croak "'critical' must be a hashref";
        }

        # Test if ID is unique
        my $metric_id = _metric_id( $metric );
        if ( exists $unique_ids{ $metric_id } ) {
            croak "One of the metric IDs ($metric_id) is not unique, try adding \'suffix\'; metric: " . Dumper( $metric );
        }
        $unique_ids{ $metric_id } = 1;
    }
}

sub _munin_print_autoconf($) {
    print "yes\n";
}

sub _munin_print_config($) {
    my $args = shift;

    print "graph_title " . $args->{ title } . "\n";
    print "graph_info " . $args->{ info } . "\n";
    print "graph_category " . ( $args->{ category } // _default_category() ) . "\n";
    print "graph_args " . ( $args->{ args } // _default_args() ) . "\n";
    print "graph_vlabel " . ( $args->{ vlabel } ) . "\n";
    if ( $args->{ scale } ) {
        print "graph_scale " . ( $args->{ scale } ) . "\n";
    }

    foreach my $metric ( @{ $args->{ metrics } } ) {
        my $metric_id = _metric_id( $metric );

        print "$metric_id.label " . $metric->{ label } . "\n";

        my $color = $metric->{ color };
        $color =~ s/#//g;
        print "$metric_id.colour " . $color . "\n";

        if ( $metric->{ draw } ) {
            print "$metric_id.draw " . $metric->{ draw } . "\n";            
        }

        if ( $metric->{ warning } ) {
            my $from = _resolve_value( $metric->{ warning }->{ from } );
            my $to = _resolve_value( $metric->{ warning }->{ to } );
            print "$metric_id.warning $from:$to\n";
        }

        if ( $metric->{ critical } ) {
            my $from = _resolve_value( $metric->{ critical }->{ from } );
            my $to = _resolve_value( $metric->{ critical }->{ to } );
            print "$metric_id.critical $from:$to\n";
        }
    }
}

sub postgresql_handler() {

    my $host = $ENV{ PGHOST };
    my $port = $ENV{ PGPORT } // 5432;
    my $user = $ENV{ PGUSER };
    my $pass = $ENV{ PGPASSWORD };
    my $name = $ENV{ PGDATABASE };

    unless ( defined $host and defined $user and defined $pass and defined $name ) {
        say STDERR "PostgreSQL connection credentials are not set, falling back to default ones.";
        $host = 'localhost';
        $user = 'mediaclouduser';
        $pass = 'mediacloud';
        $name = 'mediacloud';
    }

    my $db;
    Readonly my $connect_timeout => 10;
    eval {
        local $SIG{ ALRM } = sub { die "Timed out in $connect_timeout seconds\n" }; # N.B. \n required
        eval {
            alarm( $connect_timeout );

            $db = DBIx::Simple->connect( "dbi:Pg:dbname=$name;host=$host;port=$port", $user, $pass, { RaiseError => 1 } );
        };

        # outer eval catches alarm that might fire JUST before this alarm(0)
        alarm(0);  # cancel alarm (if code ran fast)
        if ( $@ ) {
            die "$@";
        }
    };
    if ( $@ ) {
        warn "Unable to connect to PostgreSQL: $@";
    }
    return $db;
}

sub _munin_print_values($) {
    my $args = shift;

    my $db = postgresql_handler();

    foreach my $metric ( @{ $args->{ metrics } } ) {
        my $metric_id = _metric_id( $metric );

        if ( $db ) {
            # PostgreSQL might be down
            $db->begin_work;
        }

        my $value = $metric->{ value }( $db ) + 0;
        
        if ( $db ) {
            # PostgreSQL might be down
            $db->rollback;
        }

        print "$metric_id.value $value\n";
    }
}

sub plugin($) {
    my $args = shift;

    # PATH might not contain those
    local $ENV{ PATH } = "/usr/local/bin:/usr/local/sbin:$ENV{PATH}";

    _validate_arguments( $args );

    if ( defined $ARGV[0] ) {
        if ( $ARGV[0] eq 'autoconf' ) {
            _munin_print_autoconf( $args );
        } elsif ( $ARGV[0] eq 'config' ) {
            _munin_print_config( $args );
        } else {
            croak 'Unknown argument: ' . $ARGV[0];
        }
    } else {
        _munin_print_values( $args );
    }

    return 0;
}

sub should_expect_weekend_traffic()
{
    Readonly my $SUNDAY => 0;
    Readonly my $MONDAY => 1;
    Readonly my $TUESDAY => 2;
    Readonly my $WEDNESDAY => 3;
    Readonly my $THURSDAY => 4;
    Readonly my $FRIDAY => 5;
    Readonly my $SATURDAY => 6;

    # Time::localtime
    my $wday = localtime->wday;
    my $hour = localtime->hour;

    # We get a lower weekend traffic From Friday 12:00 to Monday 18:00
    if ( $wday == $SATURDAY or $wday == $SUNDAY
         or ( $wday == $FRIDAY and $hour >= 12 )
         or ( $wday == $MONDAY and $hour < 18 ) ) {

        return 1;
    } else {
        return 0;
    }
}

1;
