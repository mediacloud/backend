package MediaWords::Util::HTML;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various functions for manipulating html

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(html_strip);

# various functions for editing feed and medium tags

use strict;
use HTML::StripPP;
use HTML::Entities qw( decode_entities  );
use Devel::Peek qw(Dump);
use Encode;
use List::Util qw(min);
use Memoize;
use Tie::Cache;

# Cache output of html_strip() because it is likely that it is going to be called multiple times from extractor
my %_html_strip_cache;
tie %_html_strip_cache, 'Tie::Cache', {
    MaxCount => 1024,          # 1024 entries
    MaxBytes => 1024 * 1024    # 1 MB of space
};

memoize 'html_strip', SCALAR_CACHE => [ HASH => \%_html_strip_cache ];

# provide a procedural interface to HTML::Strip
# use HTML::StripPP instead of HTML::Strip b/c HTML::Strip mucks up the encoding
sub html_strip($)
{
    my ( $html ) = @_;

    return defined( $html ) ? HTML::StripPP::strip( $html ) : '';
}

1;
