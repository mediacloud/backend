package MediaWords::Util::Web::UserAgent::HTMLRedirects;

#
# Implements various ways to to HTML redirects
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.util.web.ua.html_redirects' );

1;
