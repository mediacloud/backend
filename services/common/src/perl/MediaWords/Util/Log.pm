package MediaWords::Util::Log;

#
# Logging helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;

require Exporter;
our @ISA    = qw/ Exporter /;
our @EXPORT = qw/ dump_terse /;

# Prints out an object in a single line
sub dump_terse($)
{
    my $object = shift;

    local $Data::Dumper::Indent    = 0;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Deparse   = 1;

    my $str = Data::Dumper::Dumper( $object );
    $str =~ s/[\n\r]/ /g;
    return $str;
}

1;
