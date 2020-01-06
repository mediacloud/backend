package MediaWords::Feed::Parse;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.feed.parse' );

1;
