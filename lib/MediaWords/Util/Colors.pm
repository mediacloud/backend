package MediaWords::Util::Colors;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Color::Mix;

# util functions that help dealing with colors, including color pallette generation

my $_mc_colors = [
    '1f77b4', 'aec7e8', 'ff7f0e', 'ffbb78', '2ca02c', '98df8a', 'd62728', 'ff9896', '9467bd', 'c5b0d5',
    '8c564b', 'c49c94', 'e377c2', 'f7b6d2', '7f7f7f', 'c7c7c7', 'bcbd22', 'dbdb8d', '17becf', '9edae5',
    '84c4ce', 'ffa779', 'cc5ace', '6f11c9', '6f3e5d'
];

# return the same color for the same set / id combination every time this function
# is called
sub get_consistent_color
{
    my ( $db, $set, $id ) = @_;

    # always return grey for null or not typed values
    return '999999' if ( grep { lc( $id ) eq $_ } ( 'null', 'not typed' ) );

    my ( $color ) = $db->query( 'select color from color_sets where color_set = ? and id = ?', $set, $id )->flat;

    return $color if ( $color );

    my $set_colors = $db->query( 'select color from color_sets where color_set = ?', $set )->flat;

    my $existing_colors = {};
    map { $existing_colors->{ $_ } = 1 } @{ $set_colors };

    # use the hard coded pallete of 25 colors if possible
    my $new_color;
    for my $c ( @{ $_mc_colors } )
    {
        if ( !$existing_colors->{ $c } )
        {
            $new_color = $c;
            last;
        }
    }

    # otherwise, just generate a random color
    if ( !$new_color )
    {
        my $color_mix = Color::Mix->new;
        my $colors = [ $color_mix->analogous( '0000ff', 255, 255 ) ];

        $new_color = $colors->[ int( rand() * 255 ) ];
    }

    $db->create( 'color_sets', { color_set => $set, id => $id, color => $new_color } );

    return $new_color;
}

1;
