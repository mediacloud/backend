package MediaWords::CommonLibs;
use MediaWords::CommonLibs;

use 5.8.8;

require Exporter;
our @ISA = qw(Exporter);

use strict;
use warnings;

use Perl6::Say;

#use mro     ();
#use feature ();
use Data::Dumper;

use List::Util;
use List::MoreUtils;

sub import
{
    use Data::Dumper();

    warnings->import();
    strict->import();
    Data::Dumper->export_to_level( 1,, @Data::Dumper::Export );

    {
        no strict;
        require Readonly;
        Readonly->export_to_level( 1, undef, @Readonly::Export );
    }

    #List::Util->export_to_level( 1, , @List::Util::EXPORT_OK );
    #List::MoreUtils->export_to_level( 1,, @List::MoreUtils::EXPORT_OK );

    MediaWords::CommonLibs->export_to_level( 1,, qw ( say ) );

    {
        no strict;
        use Readonly;
        MediaWords::CommonLibs->export_to_level( 1,, qw ( Readonly ) );
    }

    {
        no strict;

        #require Readonly;
        *{ caller() . '::say' } = \&say;
    }
}

1;
