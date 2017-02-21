package MediaWords::Solr::Query;

=head1 NAME MediaWords::Solr::Query - functions for parsing solr queries

=head1 SYNOPSIS

my $tsquery = MediaWords::Solr::Query::convert_to_tsquery( "foo and bar" )

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.solr.query' );

1;
