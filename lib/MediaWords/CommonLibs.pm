package MediaWords::CommonLibs;

use strict;
use warnings;

use feature qw/ :5.22 /;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

require Exporter;
our @ISA = qw(Exporter);

use Data::Dumper;
use Readonly;

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
