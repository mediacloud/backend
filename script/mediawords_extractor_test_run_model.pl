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
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::HTML;

use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::MoreUtils qw( uniq distinct each_array :all );
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use Text::Trim;

use Data::Dumper;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractorTest;
use Data::Compare;
use Storable;
use 5.14.2;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Mallet::CrfWrapper;

sub main
{
    my $file;

    my $_feature_file;
    my $_model_file;

    GetOptions(
        'feature_file=s' => \$_feature_file,
        'model_file=s'   => \$_model_file,
    ) or die;

    die unless defined( $_feature_file ) and defined( $_model_file );

    open( my $fh, '<', $_feature_file )
      or die "cannot open $_feature_file: $! ";

    my @all_file_lines = <$fh>;

    close( $fh );

    my $predictions = Mallet::CrfWrapper::run_model_inline_java_data_array( $_model_file, \@all_file_lines );

    say join "\n", @{ $predictions };
}

main();
