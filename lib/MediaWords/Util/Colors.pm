package MediaWords::Util::Colors;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# util functions that help dealing with colors, including color pallette generation

use strict;

my $_mc_colors = [
    '1f77b4', 'aec7e8', 'ff7f0e', 'ffbb78', '2ca02c', '98df8a', 'd62728', 'ff9896', '9467bd', 'c5b0d5',
    '8c564b', 'c49c94', 'e377c2', 'f7b6d2', '7f7f7f', 'c7c7c7', 'bcbd22', 'dbdb8d', '17becf', '9edae5',
    '84c4ce', 'ffa779', 'cc5ace', '6f11c9', '6f3e5d'
];

# return a pallete of $num_colors distinct colors.  if format is 'rgb()', return in rgb() format, otherwise return in hex format.
sub get_colors
{
    my ( $num_colors, $format ) = @_;

    my $colors;
    if ( $num_colors <= @{ $_mc_colors } )
    {
        $colors = [ ( @{ $_mc_colors } )[ 0 .. ( $num_colors - 1 ) ] ];
    }
    else
    {
        use Color::Mix;
        my $color_mix = Color::Mix->new;
        $colors = [ $color_mix->analogous( '0000ff', $num_colors, $num_colors ) ];
    }

    if ( !$format || $format eq 'hex' )
    {
        return $colors;
    }
    elsif ( $format eq 'rgb()' )
    {
        return [ map { get_rgbp_format( $_ ) } @{ $colors } ];
    }
    else
    {
        die( "Unknown format '$format'" );
    }
}

# accept hex format [ FFFFFF ] and return rgb() format [ rgb(255,255,255) ]
sub get_rgbp_format
{
    my ( $hex ) = @_;

    return 'rgb(' .
      hex( substr( $hex, 0, 2 ) ) . ',' .
      hex( substr( $hex, 2, 2 ) ) . ',' .
      hex( substr( $hex, 4, 2 ) ) . ')';
}

1;
