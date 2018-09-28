package MediaWords::DBI::DownloadTexts;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.download_texts' );

1;
