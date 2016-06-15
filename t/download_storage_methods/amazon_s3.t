use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
    use lib "$FindBin::Bin/../";
    use lib "$FindBin::Bin/";
}

use MediaWords::KeyValueStore::AmazonS3;

require 'amazon_s3_set_credentials_from_env.inc.pl';
set_amazon_s3_test_credentials_from_env_if_needed();

require 'amazon_s3_tests.inc.pl';

my $s3_handler_class = 'MediaWords::KeyValueStore::AmazonS3';
test_amazon_s3( $s3_handler_class );
