package MediaWords::Crawler::Handler::AbstractHandler;

#
# Abstract class for implementing crawler download handler.
#

use strict;
use warnings;

use Moose::Role;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

#
# Required methods
#

# Handle download that was just fetched by preprocessing and storing it
#
# Returns arrayref of story IDs to be extracted, for example:
#
# * 'content' downloads return an arrayref with a single story ID for the
#   content download
# * 'feed/syndicated' downloads return an empty arrayref because there's
#   nothing to be extracted from a syndicated feed
# * 'feed/web_page' downloads return an arrayref with a single 'web_page'
#   story to be extracted
requires 'handle_download';

no Moose;    # gets rid of scaffolding

1;
