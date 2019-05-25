use strict;
use warnings;

use Data::Dumper;
use Test::Deep;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Util::SQL;
use MediaWords::Test::DB::Create;

sub _is_new_compare($$$$;$)
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

sub _is_new_test_story($$$)
{
    my ( $db, $story, $num ) = @_;

    my $publish_date   = $story->{ publish_date };
    my $plus_two_days  = MediaWords::Util::SQL::increment_day( $publish_date, 2 );
    my $minus_two_days = MediaWords::Util::SQL::increment_day( $publish_date, -2 );

    _is_new_compare( $db, "$num identical", 0, $story );

    _is_new_compare( $db, "$num media_id diff",             1, $story, { media_id => $story->{ media_id } + 1 } );
    _is_new_compare( $db, "$num url+guid diff, title same", 0, $story, { url      => "diff", guid => "diff" } );
    _is_new_compare( $db, "$num title+url diff, guid same", 0, $story, { url      => "diff", title => "diff" } );
    _is_new_compare( $db, "$num title+guid diff, url same", 1, $story, { guid     => "diff", title => "diff" } );

    _is_new_compare( $db, "$num date +2days", 1, $story, { url => "diff", guid => "diff", publish_date => $plus_two_days } );
    _is_new_compare( $db, "$num date -2days", 1, $story,
        { url => "diff", guid => "diff", publish_date => $minus_two_days } );
}

sub test_is_new($)
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6 ]
        },
        D => { E => [ 7, 8, 9 ] }
    };

    my $media = MediaWords::Test::DB::Create::create_test_story_stack( $db, $data );

    my $stories = {};
    for my $m ( values( %{ $media } ) )
    {
        for my $f ( values( %{ $m->{ feeds } } ) )
        {
            while ( my ( $num, $story ) = each( %{ $f->{ stories } } ) )
            {
                _is_new_test_story( $db, $story, $num );
            }
        }
    }
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();
    test_is_new( $db );

    done_testing();
}

main();
