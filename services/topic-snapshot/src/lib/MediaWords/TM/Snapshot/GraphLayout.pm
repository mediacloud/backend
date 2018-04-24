package MediaWords::TM::Snapshot::GraphLayout;

#
# Proxy perl module for python snapshot graph layout
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.tm.snapshot.graph_layout' );

1;
