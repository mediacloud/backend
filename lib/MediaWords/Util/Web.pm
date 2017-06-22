package MediaWords::Util::Web;

#
# Various functions to make downloading web pages easier and faster, including
# parallel and cached fetching.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.util.web' );

use MediaWords::Util::Web::UserAgent::Request;
use MediaWords::Util::Web::UserAgent::Response;
use MediaWords::Util::Web::UserAgent;

1;
