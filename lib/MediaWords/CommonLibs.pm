package MediaWords::CommonLibs;

use strict;
use warnings;

use feature qw/ :5.22 /;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

require Exporter;
our @ISA = qw(Exporter);

use Data::Dumper;
use Readonly;

use MediaWords::Util::Config;

our @LOGGER = qw(FATAL ERROR WARN INFO DEBUG TRACE LOGDIE LOGWARN LOGCARP LOGCLUCK LOGCONFESS LOGCROAK);

our @EXPORT = ( @Readonly::EXPORT, @Data::Dumper::EXPORT, @LOGGER );

sub import
{
    my ( $class, @isa ) = @_;

    my $caller = caller;

    strict->import();
    warnings->import();
    feature->import( qw( :5.22 ) );

    if ( scalar @isa )
    {
        foreach my $isa ( @isa )
        {
            if ( eval "require $isa" )
            {
                no strict 'refs';
                push @{ "${caller}::ISA" }, $isa;
            }
        }
    }

    $class->export_to_level( 1, $caller );

    return;
}

use Log::Log4perl;
use FindBin;

# initialize the log once.  for some reason, the init doesn't take sometimes if we just
# call it during module load.
my $_init_log;

sub init_log
{
    return if ( $_init_log );

    Log::Log4perl::init( MediaWords::Util::Config::get_mc_root_dir() . "/log4perl.conf" );

    # makes default category be the calling package rather than mediawords.logger
    Log::Log4perl::wrapper_register( __PACKAGE__ );

    $_init_log = 1;
}

# can't get default package to work unless these are defined explicitly.
# the goofy '$_init_log || init_log' call is to avoid init_log function call with every log statement
sub TRACE { $_init_log || init_log; Log::Log4perl::get_logger->trace( @_ ) }
sub DEBUG { $_init_log || init_log; Log::Log4perl::get_logger->debug( @_ ) }
sub INFO  { $_init_log || init_log; Log::Log4perl::get_logger->info( @_ ) }
sub WARN  { $_init_log || init_log; Log::Log4perl::get_logger->warn( @_ ) }
sub ERROR { $_init_log || init_log; Log::Log4perl::get_logger->error( @_ ) }
sub FATAL { $_init_log || init_log; Log::Log4perl::get_logger->fatal( @_ ) }

sub LOGWARN { $_init_log || init_log; Log::Log4perl::get_logger->logwarn( @_ ) }
sub LOGDIE  { $_init_log || init_log; Log::Log4perl::get_logger->logdie( @_ ) }

sub LOGCARP    { $_init_log || init_log; Log::Log4perl::get_logger->logcarp( @_ ) }
sub LOGCLUCK   { $_init_log || init_log; Log::Log4perl::get_logger->logcluck( @_ ) }
sub LOGCROAK   { $_init_log || init_log; Log::Log4perl::get_logger->loccroak( @_ ) }
sub LOGCONFESS { $_init_log || init_log; Log::Log4perl::get_logger->logconfess( @_ ) }

$SIG{ INT } = sub { DEBUG( "^c exiting  ..." ); exit( 1 ) };

1;
