use strict;
use warnings;

use FindBin;
use MediaWords::KeyValueStore::AmazonS3;

require "$FindBin::Bin/helpers/amazon_s3_set_credentials_from_env.inc.pl";
set_amazon_s3_test_credentials_from_env_if_needed();

require "$FindBin::Bin/helpers/amazon_s3_tests.inc.pl";

my $s3_handler_class = 'MediaWords::KeyValueStore::AmazonS3';
test_amazon_s3( $s3_handler_class );
