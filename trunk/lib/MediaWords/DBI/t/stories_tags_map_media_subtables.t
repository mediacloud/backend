use strict;
use warnings;

use Test::NoWarnings;
use Test::More tests => 6 + 1;

BEGIN
{
    use_ok( 'MediaWords::DBI::StoriesTagsMapMediaSubtables' );
}

require_ok( 'MediaWords::DBI::StoriesTagsMapMediaSubtables' );

is( MediaWords::DBI::StoriesTagsMapMediaSubtables::isNonnegativeInteger( -1 ),   '', '-1 is not non-negative' );
is( MediaWords::DBI::StoriesTagsMapMediaSubtables::isNonnegativeInteger( 1 ),    1,  '1 is a non-negative integer' );
is( MediaWords::DBI::StoriesTagsMapMediaSubtables::isNonnegativeInteger( 1.3 ),  '', '1.3 is not an integer' );
is( MediaWords::DBI::StoriesTagsMapMediaSubtables::isNonnegativeInteger( -1.3 ), '', '-1.3 is not a non-negative integer' );
