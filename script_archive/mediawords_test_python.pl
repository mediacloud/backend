#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::MoreUtils qw( :all);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );

use Data::Dumper;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractorTest;
use MediaWords::Util::HeuristicExtractor;
use MediaWords::Util::MaxEntExtractor;
use MediaWords::Util::CrfExtractor;

use Data::Compare;
use Storable;
use 5.14.2;

use Inline Python => '/home/dlarochelle/git_dev/mediacloud/python_scripts/solr_query_wordcount_timer.py';

# do a test run of the text extractor
sub main
{
    say "Foo";
    my $solr = solr_connection();
    my $result = get_word_counts( $solr, 'sentence:the', '2013-08-10', 100 );

    say Dumper( $result );
}

main();
