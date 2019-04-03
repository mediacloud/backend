package MediaWords::Solr::Query::Parse;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.solr.query.parse' );

1;
