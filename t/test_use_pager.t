use strict;
use warnings;

# test the use_pager logic in Handler.pm that reads and sets the use_pager
# flag that determines whether to use the pager for a given media source

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More tests => 11;
use Test::NoWarnings;

use English '-no_match_vars';

BEGIN
{
    use_ok( 'MediaWords::DB' );
    use_ok( 'MediaWords::Crawler::Handler' );
    use_ok( 'MediaWords::Test::DB' );
}

sub test_use_pager
{
    my ( $db ) = @_;

    my $medium = {
        name      => "test use pager $PROCESS_ID",
        url       => "url://test/use/pager/$PROCESS_ID",
        moderated => 't',
        use_pager => 't'
    };
    $medium = $db->create( 'media', $medium );

    is( MediaWords::Crawler::Handler::use_pager( $medium ), 1, "use_pager true" );

    $medium = $db->query( "update media set use_pager = null where media_id = ? returning *", $medium->{ media_id } )->hash;
    is( MediaWords::Crawler::Handler::use_pager( $medium ), 1, "null use_pager" );

    $medium = $db->query( "update media set use_pager = 'f' where media_id = ? returning *", $medium->{ media_id } )->hash;
    is( MediaWords::Crawler::Handler::use_pager( $medium ), 0, "use_pager false" );

    $medium = $db->query( "update media set use_pager = null where media_id = ? returning *", $medium->{ media_id } )->hash;
    MediaWords::Crawler::Handler::set_use_pager( $db, $medium, 'http://foo.bar' );
    $medium = $db->find_by_id( 'media', $medium->{ media_id } );
    is( MediaWords::Crawler::Handler::use_pager( $medium ), 1, "set_use_pager use_pager true" );

    $medium = $db->query( <<END, $medium->{ media_id } )->hash;
update media set use_pager = null, unpaged_stories = 99 where media_id = ? returning *
END
    MediaWords::Crawler::Handler::set_use_pager( $db, $medium, undef );
    $medium = $db->find_by_id( 'media', $medium->{ media_id } );
    is( MediaWords::Crawler::Handler::use_pager( $medium ), 1, "100th unpaged story: use_pager true" );

    MediaWords::Crawler::Handler::set_use_pager( $db, $medium, undef );
    $medium = $db->find_by_id( 'media', $medium->{ media_id } );
    is( MediaWords::Crawler::Handler::use_pager( $medium ), 0, "100th unpaged story: use_pager false" );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;

            test_use_pager( $db );

            Test::NoWarnings::had_no_warnings();
        }
    );
}

main();
