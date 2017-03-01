use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More tests => 4;

use MediaWords::Test::DB;
use MediaWords::TM::Mine;

sub test_postgres_regex_match($)
{
    my $db = shift;

    my $regex = '(?: [[:<:]]alt-right | [[:<:]]alt[[:space:]]+right | [[:<:]]alternative[[:space:]]+right )';

    {
        # Match
        my $strings = [ 'This is a string describing alt-right and something else.' ];
        ok( MediaWords::TM::Mine::postgres_regex_match( $db, $strings, $regex ) );
    }

    {
        # No match
        my $strings = [ 'This is a string describing just something else.' ];
        ok( !MediaWords::TM::Mine::postgres_regex_match( $db, $strings, $regex ) );
    }

    {
        # One matching string
        my $strings = [
            'This is a string describing something else.',    #
            'This is a string describing alt-right.',         #
        ];
        ok( MediaWords::TM::Mine::postgres_regex_match( $db, $strings, $regex ) );
    }

    {
        # Two non-matching strings
        my $strings = [
            'This is a string describing something else.',          #
            'This is a string describing something else again.',    #
        ];
        ok( !MediaWords::TM::Mine::postgres_regex_match( $db, $strings, $regex ) );
    }
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_postgres_regex_match( $db );
        }
    );
}

main();
