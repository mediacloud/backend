package MediaWords::ImportStories::Dummy;

# dummy sub class for testing ImportStories

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::ImportStories';

sub get_new_stories
{
    # we're just testing specific methods for now, so this function doesn't have to do anything useful
    return [];
}

1;
