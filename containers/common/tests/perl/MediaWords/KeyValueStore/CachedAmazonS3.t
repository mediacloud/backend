#!/usr/bin/env prove

use strict;
use warnings;

use FindBin;
use MediaWords::KeyValueStore::CachedAmazonS3;
use Readonly;

require "$FindBin::Bin/helpers/amazon_s3_tests.inc.pl";

my $s3_handler_class = 'MediaWords::KeyValueStore::CachedAmazonS3';
Readonly my $create_mock_download => 1;
test_amazon_s3( $s3_handler_class, $create_mock_download );
