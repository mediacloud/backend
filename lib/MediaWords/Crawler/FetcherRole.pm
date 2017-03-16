package MediaWords::Crawler::FetcherRole;

#
# Moose role that download fetchers should implement
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;

# Fetch the $download and return the response.
#
# In addition to the basic HTTP request with the user agent options supplied by
# MediaWords::Util::Web::UserAgent object, the implementation should:
#
# * fixes common url mistakes like doubling http: (http://http://google.com).
# * follows meta refresh redirects in the response content
# * adds domain specific http auth specified in mediawords.yml
# * implements a very limited amount of site specific fixes
requires 'fetch_download';

1;
