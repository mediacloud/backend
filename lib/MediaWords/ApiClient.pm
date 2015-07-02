package MediaWords::ApiClient;

# Wrapper library to allow using the Python API Client from Perl.

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Data::Dumper;

use Inline 'Python' => 'from mediacloud.api import MediaCloud';
use Inline 'Python' => 'from mediacloud.api import AdminMediaCloud';

1;
