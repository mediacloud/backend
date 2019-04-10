#!/usr/bin/env prove

use strict;
use warnings;

use FindBin;
use MediaWords::KeyValueStore::AmazonS3;

require "$FindBin::Bin/helpers/amazon_s3_tests.inc.pl";

my $s3_handler_class = 'MediaWords::KeyValueStore::AmazonS3';
test_amazon_s3( $s3_handler_class );
