#!/usr/bin/env prove

use strict;
use warnings;

use Test::More;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::DB;

use MediaWords::DBI::Stories::GuessDate;

sub test_assign_date_guess_method($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, 1, 1, 10 );

    my $story = $db->query( "select * from stories limit 1 offset 3" )->hash;

    {
        MediaWords::DBI::Stories::GuessDate::assign_date_guess_method( $db, $story, 'undateable' );

        my $got_tag = $db->query( <<SQL, $story->{ stories_id } )->hash;
select t.* from tags t join stories_tags_map stm using ( tags_id ) where stm.stories_id = ?
SQL

        is( $got_tag->{ tag }, 'undateable', "assign_date_guess_method: undateable" );
    }
    {
        MediaWords::DBI::Stories::GuessDate::assign_date_guess_method( $db, $story, 'foo bar / and ; baz' );

        my $got_tag = $db->query( <<SQL, $story->{ stories_id } )->hash;
select t.* from tags t join stories_tags_map stm using ( tags_id ) where stm.stories_id = ?
SQL

        is( $got_tag->{ tag }, 'unknown', "assign_date_guess_method: unknown" );
    }
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_assign_date_guess_method( $db );

    done_testing();
}

main();
