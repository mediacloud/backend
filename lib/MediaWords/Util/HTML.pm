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

use constant MAX_SEGMENT_LENGTH => 14000;

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
    my $html = shift;

    unless ( defined( $html ) )
    {
        return '';
    }

    my $html_length = length( $html );

    if ( ( $html_length > MAX_SEGMENT_LENGTH ) )
    {
        my $str_pos = 0;

        my $ret;

        while ( $str_pos < $html_length )
        {
            my $new_line_pos = index( $html, "\n", $str_pos + 5000 );

            my $new_line_segment_length;

            if ( $new_line_pos == -1 )
            {
                $new_line_segment_length = MAX_SEGMENT_LENGTH;
            }
            else
            {
                $new_line_segment_length = $new_line_pos - $str_pos;
            }

            my $segment_length = min( $new_line_segment_length, MAX_SEGMENT_LENGTH );

            my $token_end_pos = index( $html, '>', $str_pos + 5000 ) + 1;

            my $token_boundary_segment_length;

            if ( $token_end_pos == 0 )
            {
                $token_boundary_segment_length = MAX_SEGMENT_LENGTH;
            }
            else
            {
                $token_boundary_segment_length = $token_end_pos - $str_pos;
            }

            $segment_length = min( $segment_length, $token_boundary_segment_length );

            $ret .= HTML::StripPP::strip( substr( $html, $str_pos, $segment_length ) );
            $str_pos += $segment_length;
        }

        return $ret;
    }

    return HTML::StripPP::strip( $html ) || '';
}

1;
