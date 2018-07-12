package MediaWords::Crawler::HandlerRole;

#
# Moose role that download handlers should implement
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;

# Handle the download (response object) somehow, e.g. store it, parse if
# it is a feed, add new stories derived from it, etc.
requires 'handle_response';

1;
