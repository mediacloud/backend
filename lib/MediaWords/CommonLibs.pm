package MediaWords::CommonLibs;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

require Exporter;
our @ISA = qw(Exporter);

use strict;
use warnings;

# Don't emit "~~", "given" and "when" warnings
use feature "lexical_subs";
no if $] >= 5.017011, warnings qw(experimental::smartmatch experimental::lexical_subs);

use Data::Dumper;

use List::Util;
use List::MoreUtils;

sub import
{
    use Data::Dumper();

    feature->import( ':5.18' );
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

    {
        no strict;
        use Readonly;
        MediaWords::CommonLibs->export_to_level( 1,, qw ( Readonly ) );
    }

}

1;
