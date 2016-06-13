use strict;
use warnings;

# test query continuations

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More;

use MediaWords::DB;
use MediaWords::Test::DB;

sub test_continuation
{
    my ( $db ) = @_;

    $db->query( "create temporary table foo ( foo int )" );

    my $max_val    = 1000;
    my $chunk_size = 100;

    my $vals = [];
    for my $val ( 1 .. $max_val )
    {
        $db->query( "insert into foo values (?)", $val );
        push( @{ $vals }, $val );
    }

    my $continuation_id;
    my $chunk_num = 1;
    while ( @{ $vals } )
    {
        my $expected_vals = [];
        map { push( @{ $expected_vals }, shift( @{ $vals } ) ) } ( 1 .. $chunk_size );

        my $got_vals;
        if ( !$continuation_id )
        {
            ( $got_vals, $continuation_id ) = $db->query_and_create_continuation_id( <<SQL, [], $chunk_size );
select foo from foo order by foo
SQL
        }
        else
        {
            ( $got_vals, $continuation_id ) = $db->query_continuation( $continuation_id );
        }

        my $expected_list = join( ',', @{ $expected_vals } );
        my $got_list = join( ',', map { $_->{ foo } } @{ $got_vals } );

        is( $expected_list, $got_list, "chunk " . $chunk_num++ . " vals" );
    }

    my ( $final_vals, $final_continuation_id ) = $db->query_continuation( $continuation_id );

    ok( !@{ $final_vals },       "final values is empty" );
    ok( !$final_continuation_id, "final continuation_id is undef" );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;

            test_continuation( $db );
        }
    );

    done_testing();
}

main();
