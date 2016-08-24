package MediaWords::Crawler::Handler::Feed::AbstractFeedHandler;

#
# Abstract class for implementing crawler feed download handler.
#

use strict;
use warnings;

use Moose::Role;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

#
# Required methods
#

# Handle feed download that was just fetched by adding new stories from it
#
# Returns arrayref of story IDs to be extracted, for example:
#
# * 'feed/syndicated' downloads return an empty arrayref because there's
#   nothing to be extracted from a syndicated feed
# * 'feed/web_page' downloads return an arrayref with a single 'web_page'
#   story to be extracted
requires 'add_new_stories';

no Moose;    # gets rid of scaffolding

1;
