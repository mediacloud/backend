package MediaWords::Solr::Query;

=head1 NAME MediaWords::Solr::Query - functions for parsing solr queries

=head1 SYNOPSIS

my $tsquery = MediaWords::Solr::Query::convert_to_tsquery( "foo and bar" )

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::Config;
use Inline Python => MediaWords::Util::Config::get_mc_python_dir() . '/mediawords/solr/query.py';

1;
