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
use List::MoreUtils qw( uniq distinct :all );
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use Lingua::EN::Sentence::MediaWords;
use Text::Trim;

use Data::Dumper;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractorTest;
use Data::Compare;
use Storable;
use 5.14.2;

my $_re_generate_cache = 0;
my $_test_sentences    = 0;

my $_download_data_load_file;
my $_download_data_store_file;
my $_dont_store_preprocessed_lines;
my $_dump_training_data_csv;

sub words_on_line
{
    my ( $line ) = @_;

    my $ret = [];

    trim( $line );

    return $ret if $line eq '';
    return $ret if $line eq ' ';

    my @words = split /\s+/, $line;

    $ret = [ uniq( @words ) ];

    return $ret;
}

sub get_word_counts
{
    my ( $downloads ) = @_;

    my $word_counts = {};

    foreach my $download ( @{ $downloads } )
    {
        my $line_count = scalar( @{ $download->{ line_info } } );

        die unless scalar( @{ $download->{ line_info } } ) == scalar( @{ $download->{ preprocessed_lines } } );

        my $line_infos         = $download->{ line_info };
        my $preprocessed_lines = $download->{ preprocessed_lines };

        my $ea =  each_arrayref ( $line_infos, $preprocessed_lines );

	while ( my ( $line_info, $preprocessed_line ) = $ea->() )
        {
            if ( $line_info->{ auto_excluded } )
            {
                next if $preprocessed_line eq '';
                next if $preprocessed_line eq ' ';

                #say Dumper($preprocessed_line );

                my @words = @{ words_on_line( $preprocessed_line ) };

                foreach my $word ( @words )
                {
                    $word_counts->{ $word } //= 0;
                    $word_counts->{ $word }++;
                }
            }
        }
    }

    return $word_counts;

}

# do a test run of the text extractor
sub main
{
    my $file;

    GetOptions(
        'file|f=s' => \$file,

        # 'download_data_load_file=s'     => \$_download_data_load_file,
        # 'download_data_store_file=s'    => \$_download_data_store_file,
        # 'dont_store_preprocessed_lines' => \$_dont_store_preprocessed_lines,
        # 'dump_training_data_csv'        => \$_dump_training_data_csv,
    ) or die;

    die unless $file;

    my $downloads = retrieve( $file );

    #say Dumper( $downloads );

    say STDERR "retrieved file";

    my $word_counts = {};

    foreach my $download ( @{ $downloads } )
    {
        foreach my $preprocessed_line ( @{ $download->{ preprocessed_lines } } )
        {

            next if $preprocessed_line eq '';
            next if $preprocessed_line eq ' ';

            #say Dumper($preprocessed_line );

            my @words = split /\s+/, $preprocessed_line;

            foreach my $word ( @words )
            {
                $word_counts->{ $word } //= 0;
                $word_counts->{ $word }++;
            }
        }

        #last;

    }

    $word_counts = get_word_counts( $downloads );

    my @words = keys %{ $word_counts };

    @words = sort { $word_counts->{ $b } <=> $word_counts->{ $a } } @words;

    foreach my $word ( @words[ 0 .. 10 ] )
    {
        say "$word " . $word_counts->{ $word };
    }

    exit;
    my %top_words = map { $_ => 1 }  @words[ 0 .. 500 ];
    
    foreach my $download ( @{ $downloads } )
    {

        #say Dumper( keys %{ $download } );

        #say Dumper ( $download->{ line_should_be_in_story } );

        my $last_in_story_line;

        my $line_num = 0;

        foreach my $line ( @{ $download->{ line_info } } )
        {

            if ( !$line->{ auto_excluded } )
            {

                #say STDERR Dumper( $line );

                #exit;
            }

            my $line_number = $line->{ line_number };

            if ( defined( $last_in_story_line ) )
            {
                $line->{ distance_from_previous_in_story_line } = $line_number - $last_in_story_line;
            }

            $line->{ class } = $download->{ line_should_be_in_story }->{ $line_number } // 'excluded';

            if ( $line->{ class } ne 'excluded' )
            {
                $last_in_story_line = $line_number;
            }
        }

        #say Dumper ( $download->{ line_info } );

        #last;
    }

    my $banned_fields = {};

    {
        my @banned_fields = qw ( line_number auto_excluded auto_exclude_explanation copyright_copy );

        foreach my $banned_field ( @banned_fields )
        {
            $banned_fields->{ $banned_field } = 1;
        }
    }

    foreach my $download ( @{ $downloads } )
    {
        foreach my $line ( @{ $download->{ line_info } } )
        {

            next if $line->{ auto_excluded } == 1;

            my @feature_fields = sort ( keys %{ $line } );

            #say join "\n", @feature_fields;

            foreach my $feature_field ( @feature_fields )
            {
                next if defined( $banned_fields->{ $feature_field } );

                next if $feature_field eq 'class';

                next if ( !defined( $line->{ $feature_field } ) );
                next if ( $line->{ $feature_field } eq '0' );
                next if ( $line->{ $feature_field } eq '' );

                my $field_value = $line->{ $feature_field };

                #next if ($field_valuene '1' &&$field_valuene '0' );

                if ( $field_value eq '1' )
                {
                    print "$feature_field";
                    print "=" . $field_value;    # || 0;
                    print " ";
                }
                else
                {
                    my $val = 1.0;

                    #say STDERR $field_value;
                    while ( $field_value < $val )
                    {
                        print "$feature_field" . "_lt_" . $val;
                        print " ";
                        $val /= 2;
                    }

                    # print "$feature_field";
                    # print "=" . $field_value; # || 0;
                    # print " ";

                    #exit ;
                    $val = 1.0;

                    while ( $field_value > $val )
                    {
                        print "$feature_field" . "_gt_" . $val;
                        print " ";
                        $val *= 2;
                    }
                }

            }

            say $line->{ class };

            #exit;

        }

        #exit;

    }
}

main();
