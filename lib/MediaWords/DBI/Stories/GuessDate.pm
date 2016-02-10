package MediaWords::DBI::Stories::GuessDate;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Tags;

# confirm that the date for the story is correct by changing the date_guess_method of the given
# story to 'manual'
sub confirm_date
{
    my ( $db, $story ) = @_;

    $db->query( <<END, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t, tag_sets ts
    where t.tag_sets_id = ts.tag_sets_id and
        stm.tags_id = t.tags_id and
        ts.name = 'date_guess_method' and
        stm.stories_id = ?
END

    my $t = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:manual' );
    $db->query( <<END, $story->{ stories_id }, $t->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END
}

# if the date guess method is manual, remove and replace with an ;unconfirmed' method tag
sub unconfirm_date
{
    my ( $db, $story ) = @_;

    unless ( date_is_confirmed( $db, $story ) )
    {
        say STDERR "Date for story " . $story->{ stories_id } . " is not confirmed, so not unconfirming.";
        return;
    }

    my $manual      = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:manual' );
    my $unconfirmed = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:unconfirmed' );

    $db->query( <<END, $story->{ stories_id }, $manual->{ tags_id } );
delete from stories_tags_map where stories_id = ? and tags_id = ?
END

    $db->query( <<END, $story->{ stories_id }, $unconfirmed->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END

}

# return true if the date guess method is manual, which means that the date has been confirmed
sub date_is_confirmed
{
    my ( $db, $story ) = @_;

    my $r = $db->query( <<END, $story->{ stories_id } )->hash;
select 1 from stories_tags_map stm, tags t, tag_sets ts
    where stm.tags_id = t.tags_id and
        ts.tag_sets_id = t.tag_sets_id and
        t.tag = 'manual' and
        ts.name = 'date_guess_method' and
        stm.stories_id = ?
END

    return $r ? 1 : 0;
}

# return true if the date is reliable.  a date is reliable if either of the following are true:
# * the story has one of the date_guess_method:* tags listed in reliable_methods below;
# * no date_guess_method:* tag and no date_invalid:undateable tag is associated with the story
# otherwise, the date is unreliable
sub date_is_reliable
{
    my ( $db, $story ) = @_;

    my $tags = $db->query( <<END, $story->{ stories_id } )->hashes;
select t.tag, ts.name tag_set_name
    from stories_tags_map stm
        join tags t on ( stm.tags_id = t.tags_id and stm.stories_id = ? )
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id and ts.name in ( 'date_guess_method', 'date_invalid' ) )
END

    my $tag_lookup = { date_guess_method => {}, date_invalid => {} };
    for my $tag ( @{ $tags } )
    {
        $tag_lookup->{ $tag->{ tag_set_name } }->{ $tag->{ tag } } = 1;
    }

    my $reliable_methods =
      [ qw(guess_by_og_article_published_time guess_by_url guess_by_url_and_date_text merged_story_rss manual) ];

    if ( grep { $tag_lookup->{ date_guess_method }->{ $_ } } @{ $reliable_methods } )
    {
        return 1;
    }

    if ( !$tag_lookup->{ date_invalid }->{ undateable } && !%{ $tag_lookup->{ date_guess_method } } )
    {
        return 1;
    }

    return 0;
}

# set the undateable status of the story by adding or removing the 'date_guess_method:undateable' tage
sub mark_undateable
{
    my ( $db, $story, $undateable ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_invalid:undateable' );

    $db->query( <<END, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        t.tags_id = stm.tags_id and
        ts.name = 'date_invalid' and
        stories_id = ?
END

    if ( $undateable )
    {
        $db->query( <<END, $story->{ stories_id }, $tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END
    }
}

# return true if the story has been marked as undateable
sub is_undateable
{
    my ( $db, $story ) = @_;

    my $tag = $db->query( <<END, $story->{ stories_id } )->hash;
select 1
    from stories_tags_map stm
        join tags t on ( stm.tags_id = t.tags_id )
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        stm.stories_id = ? and
        ts.name = 'date_invalid' and
        t.tag = 'undateable'
END

    return $tag ? 1 : 0;
}

my $_date_guess_method_tag_lookup = {};

# assign a tag to the story for the date guess method
sub assign_date_guess_method
{
    my ( $db, $story, $date_guess_method, $no_delete ) = @_;

    if ( !$no_delete )
    {
        for my $tag_set_name ( 'date_guess_method', 'date_invalid' )
        {
            $db->query( <<END, $tag_set_name, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where
        t.tags_id = stm.tags_id and
        ts.name = ? and
        stm.stories_id = ?
END
        }
    }

    my $tag_set_name = ( $date_guess_method eq 'undateable' ) ? 'date_invalid' : 'date_guess_method';
    my $tag_name = "$tag_set_name:$date_guess_method";

    my $date_guess_method_tag = $_date_guess_method_tag_lookup->{ $tag_name };
    if ( !$date_guess_method_tag )
    {
        $date_guess_method_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "$tag_set_name:$date_guess_method" );
        $_date_guess_method_tag_lookup->{ $tag_name } = $date_guess_method_tag;
    }

    $db->query( <<END, $story->{ stories_id }, $date_guess_method_tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END

}

1;
