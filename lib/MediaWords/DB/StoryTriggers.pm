package MediaWords::DB::StoryTriggers;

# Story trigger state

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

my $_disable_story_triggers = 0;

sub story_triggers_disabled
{
    return $_disable_story_triggers;
}

sub disable_story_triggers
{
    $_disable_story_triggers = 1;
    return;
}

sub enable_story_triggers
{
    $_disable_story_triggers = 0;
    return;
}

1;
