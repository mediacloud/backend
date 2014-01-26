package MediaWords::CommonLibs;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

require Exporter;
our @ISA = qw(Exporter);

use strict;
use warnings;

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

    #List::Util->export_to_level( 1, , @List::Util::EXPORT_OK );
    #List::MoreUtils->export_to_level( 1,, @List::MoreUtils::EXPORT_OK );
}

1;
