#!/usr/bin/env perl

#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements. See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership. The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License. You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/../foreign_modules/perl";
    use lib "$FindBin::Bin/../python_scripts/gen-perl";
}

use Thrift;
use Thrift::BinaryProtocol;
use Thrift::Socket;
use Thrift::BufferedTransport;

#use shared::SharedService;
use thrift_solr::SolrService;

#use shared::Types;
use thrift_solr::Types;

use 5.14.1;

use Data::Dumper;

my $socket = new Thrift::Socket( 'localhost', 9090 );
my $transport = new Thrift::BufferedTransport( $socket, 1024, 1024 );
my $protocol  = new Thrift::BinaryProtocol( $transport );
my $client    = new thrift_solr::SolrServiceClient( $protocol );

eval {
    $transport->open();

    my $q           = 'sentence:"birth control"';
    my $facet_field = 'media_id';
    my $fq          = [];
    my $mincount    = 1;

    my $counts = $client->media_counts( $q, $facet_field, $fq, $mincount );

    say Dumper( $counts );

    $transport->close();

};
if ( $@ )
{
    warn( Dumper( $@ ) );
}
