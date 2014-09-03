#!/usr/bin/env perl

use strict;
use warnings;

# test MediaWords::DBI::Stories::is_new

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Test::More;

BEGIN
{
    use_ok( 'MediaWords::DB' );
    use_ok( 'MediaWords::DBI::Stories' );
    use_ok( 'MediaWords::Test::DB' );
    use_ok( 'MediaWords::Util::SQL' );
}

sub test_is_new
{
    my ( $db, $label, $expected_is_new, $base_story, $story_changes ) = @_;

    my $story = { %{ $base_story } };

    while ( my ( $k, $v ) = each( %{ $story_changes } ) )
    {
        $story->{ $k } = $v;
    }

    my $is_new = MediaWords::DBI::Stories::is_new( $db, $story );

    ok( $expected_is_new ? $is_new : !$is_new, $label );
}

sub test_story
{
    my ( $db, $story, $num ) = @_;

    my $publish_date   = $story->{ publish_date };
    my $plus_two_days  = MediaWords::Util::SQL::increment_day( $publish_date, 2 );
    my $minus_two_days = MediaWords::Util::SQL::increment_day( $publish_date, -2 );

    test_is_new( $db, "$num identical", 0, $story );

    test_is_new( $db, "$num media_id diff",             1, $story, { media_id => $story->{ media_id } + 1 } );
    test_is_new( $db, "$num url+guid diff, title same", 0, $story, { url      => "diff", guid => "diff" } );
    test_is_new( $db, "$num title+url diff, guid same", 0, $story, { url      => "diff", title => "diff" } );
    test_is_new( $db, "$num title+guid diff, url same", 1, $story, { guid     => "diff", title => "diff" } );

    test_is_new( $db, "$num date +2days", 1, $story, { url => "diff", guid => "diff", publish_date => $plus_two_days } );
    test_is_new( $db, "$num date -2days", 1, $story, { url => "diff", guid => "diff", publish_date => $minus_two_days } );
}

sub run_tests
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6 ]
        },
        D => { E => [ 7, 8, 9 ] }
    };

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $data );

    my $stories = {};
    for my $m ( values( %{ $media } ) )
    {
        for my $f ( values( %{ $m->{ feeds } } ) )
        {
            while ( my ( $num, $story ) = each( %{ $f->{ stories } } ) )
            {
                test_story( $db, $story, $num );
            }
        }
    }
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            run_tests( $db );
        }
    );

    done_testing();
}

main();
