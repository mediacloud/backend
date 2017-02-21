use strict;
use warnings;

use Test::More tests => 4;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Pages;

# URLs that might fail
sub test_pages($)
{
}

sub main()
{
    my $total_entries    = 50;
    my $entries_per_page = 10;
    my $current_page     = 5;

    my $pages = MediaWords::Util::Pages->new( $total_entries, $entries_per_page, $current_page );
    is( $pages->previous_page(), 4 );
    is( $pages->next_page(),     undef );
    is( $pages->first(),         41 );
    is( $pages->last(),          50 );
}

main();
