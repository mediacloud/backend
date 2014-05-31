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
use File::Temp qw/ tempfile tempdir /;

use Mallet::CrfWrapper;

sub get_predictions_separate_exec
{
    my ( $_model_file, $current_file_lines ) = @_;

    my ( $test_data_fh, $test_data_file_name ) = tempfile( "/tmp/tested_arrayXXXXXX", SUFFIX => '.dat' );

    print $test_data_fh join "\n", @{ $current_file_lines };

    close( $test_data_fh );

    my $output =
      `./script/mediawords_extractor_test_run_model.pl --feature_file $test_data_file_name --model_file $_model_file`;

    return [ split "\n", $output ];
}

sub get_predictions
{
    my ( $_model_file, $current_file_lines ) = @_;

    #my $predictions = Mallet::CrfWrapper::run_model_with_separate_exec( $_model_file, $current_file_lines );

    my $predictions = Mallet::CrfWrapper::run_model_inline_java_data_array( $_model_file, $current_file_lines );

    #my $predictions = get_predictions_separate_exec( $_model_file, $current_file_lines );

    $predictions = [ map { rtrim $_ } @{ $predictions } ];

    return $predictions;
}

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

    my $current_file_lines = [];

    my $expected_outputs = [];

    my $total        = 0;
    my $matching     = 0;
    my $not_matching = 0;

    my $downloads = 0;
    foreach my $line ( @all_file_lines )
    {
        chomp( $line );

        #last if $downloads > 0;

        if ( $line eq '' )
        {

            push $current_file_lines, '';

            my $predictions = get_predictions( $_model_file, $current_file_lines );

            die scalar( @$expected_outputs ) . " != " . scalar( @$predictions )
              unless scalar( @$expected_outputs ) == scalar( @$predictions );

            my $ea = each_arrayref( $expected_outputs, $predictions );

            while ( ( my $expected, my $predicted ) = $ea->() )
            {
                $total++;

                if ( $expected eq $predicted )
                {
                    $matching++;
                }
                else
                {
                    $not_matching++;
                }
            }

            $expected_outputs   = [];
            $predictions        = [];
            $current_file_lines = [];

            $downloads++;
        }
        else
        {
            $line =~ /.* (.*?)$/;

            my $expected = $1;

            $line =~ s/(.*) (.*?)$/$1/;

            # say $expected;

            push $expected_outputs, $expected;

            die unless defined( $line );
            push $current_file_lines, ( $line );
        }
    }

    say "Not matching $not_matching / $total : " . ( $not_matching / $total );
}

main();
