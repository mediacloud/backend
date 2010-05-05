package MediaWords::Pg::Stopwords;

# defines is_stop_stem plperl function

use strict;

use MediaWords::Pg;
use MediaWords::Util::StopWords;

# does the stem match a stem in the stop stem list?
# size should be 'tiny' (150), 'short' (~1k), or 'long' (~4k)
sub is_stop_stem
{
    my ( $size, $stem ) = @_;

    my $stop_stem_list;

    if ( $size eq 'long' )
    {
        $stop_stem_list = MediaWords::Util::StopWords::get_long_stop_stem_lookup();
    }
    elsif ( $size eq 'short' )
    {
        $stop_stem_list = MediaWords::Util::StopWords::get_short_stop_stem_lookup();
    }
    elsif ( $size eq 'tiny' )
    {
        $stop_stem_list = MediaWords::Util::StopWords::get_tiny_stop_stem_lookup();
    }
    else
    {
        pg_log("unknown stop list size: $size");
        return 'f';
    }

    if ( $stop_stem_list->{ $stem } )
    {
        return 't';
    }
    else
    {
        return 'f';
    }
}

1;
