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

use Log::Log4perl qw(:easy);
Log::Log4perl->init(
    {
        'log4perl.rootLogger'                               => 'INFO, STDERR',
        'log4perl.appender.STDERR'                          => 'Log::Log4perl::Appender::Screen',
        'log4perl.appender.STDERR.name'                     => 'stderr',
        'log4perl.appender.STDERR.stderr'                   => '1',
        'log4perl.appender.STDERR.layout'                   => 'Log::Log4perl::Layout::PatternLayout',
        'log4perl.appender.STDERR.layout.ConversionPattern' => 'FOO %d %c: %m'
    }
);

our @EXPORT = ( @Readonly::EXPORT, @Data::Dumper::EXPORT );

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

1;
