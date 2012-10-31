#!/usr/bin/env perl
#
# Language detection module evaluation script.
#
# Usage:
# perl script_archive/langid_assess.pl --learning_dir=/Users/pypt/Desktop/global-media-20121008-plaintext/ --experiment_dir=/Users/pypt/Desktop/global-media-20121008-plaintext/

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use Getopt::Long;
use File::Basename;
use Benchmark;

# Will call subroutines by string name
no strict 'refs';

# Candidate 1 -- Lingua::Identify
# http://search.cpan.org/~ambs/Lingua-Identify-0.51/lib/Lingua/Identify.pm
use Lingua::Identify;

# Candidate 2 -- Lingua::Ident
# http://search.cpan.org/~mpiotr/Lingua-Ident-1.7/Ident.pm
use Lingua::Ident;

# Candidate 3 -- TextCat
# http://odur.let.rug.nl/vannoord/TextCat/
# http://spamassassin.apache.org/
use Mail::SpamAssassin::Plugin::TextCat;

# Candidate 4 -- Compact Language Detector (C++)
# http://code.google.com/p/chromium-compact-language-detector/
# https://github.com/ambs/Lingua-Identify-CLD
# http://www.swig.org/
use Lingua::Identify::CLD;

# Candidate 5 -- LingPipe (Java)
# http://alias-i.com/lingpipe/demos/tutorial/langid/read-me.html
use Inline::Java;

# Candidate 6 -- NLTK (Python)
# http://borel.slu.edu/crubadan/apps.html
# https://code.google.com/p/nltk/
use Inline::Python;


#
# Lingua::Identify
#
sub candidate_lingua_identify_needs_teaching
{
    # There's make-lingua-identify-language tool, but let's leave it for later.
    return 0;
}

#sub candidate_lingua_identify_teach
#{
#    my ($language_code, $text) = @_;
#}

sub candidate_lingua_identify_identify
{
    my $text = shift;

    return Lingua::Identify::langof($text);
}

sub _language_code_from_filename
{
    my $filepath = shift;
    my ( $filename, $directories, $suffix ) = fileparse( $filepath, qr/\.[^.]*/ );
    unless ($filename =~ /^\w\w\w?_\d\d\d\d$/) {
        die "Invalid filename: $filename\n";
    }
    $filename =~ s/^(\w\w\w?)_\d\d\d\d$/$1/;
    return $filename;
}

sub _contents_of_file
{
    my $filepath = shift;

    open FILE, $filepath or die "Couldn't open file: $!\n"; 
    my $contents = join('', <FILE>); 
    close FILE;

    return $contents;
}

sub langid_assess
{
    my ( $learning_dir, $experiment_dir ) = @_;
    die "Learning directory $learning_dir doesn't exist.\n" unless ( -e $learning_dir );
    die "Experiment directory $experiment_dir doesn't exist.\n" unless ( -e $experiment_dir );

    # Identification candidates
    #my @candidates = ('lingua_identify', 'lingua_ident', 'textcat', 'cld', 'lingpipe', 'nltk');
    my @candidates = ('lingua_identify');

    # Teach
    print STDERR "Teaching modules to recognize languages...\n";
    foreach my $candidate (@candidates) {

        my $needs_teaching_sub = 'candidate_' . $candidate . '_needs_teaching';
        if (&$needs_teaching_sub) {
            print STDERR "\tTeaching candidate '$candidate' to recognize languages...\n";

            my $teach_sub = 'candidate_' . $candidate . '_teach';

            my @text_files = <$learning_dir/*.txt>;
            foreach my $filepath ( @text_files )
            {
                my $language_code = _language_code_from_filename($filepath);
                my $text = _contents_of_file($filepath);

                #print STDERR "\t\tTeaching candidate '$candidate' to recognize language '$language_code'...\n";
                &$teach_sub($language_code, $text);
            }
        }
    }
    print STDERR "Done.\n";

    my @results;

    # Run experiment
    print STDERR "Running language identification experiments against candidates...\n";
    foreach my $candidate (@candidates) {
        print STDERR "\tRunning language identification experiment against candidate '$candidate'...\n";

        my $num_of_tests = 0;
        my $num_of_correct_answers = 0;

        # Start timer
        my $timer_start = new Benchmark;

        my $identify_sub = 'candidate_' . $candidate . '_identify';

        my @text_files = <$learning_dir/*.txt>;
        foreach my $filepath ( @text_files )
        {
            ++$num_of_tests;

            my $language_code = _language_code_from_filename($filepath);
            my $text = _contents_of_file($filepath);

            my $identified_language_code = &$identify_sub($text);
            if (! $identified_language_code) {
                $identified_language_code = '';
            }

            #print STDERR "\t\tCandidate: $candidate; identified code: $identified_language_code; should have been: $language_code\n";
            if ($identified_language_code eq $language_code) {
                ++$num_of_correct_answers;
            }
        }

        # End timer
        my $timer_end = new Benchmark;
        my $timer_diff = timediff($timer_end, $timer_start);
        my $timer_str = timestr($timer_diff, 'all');

        my $percent = ($num_of_correct_answers / $num_of_tests) * 100.0;

        my $result_string = "Candidate: $candidate\n";
        $result_string .= "Number of tests: $num_of_tests\n";
        $result_string .= "Number of correct answers: $num_of_correct_answers ($percent%)\n";
        $result_string .= "Time taken: $timer_str\n";
        push(@results, $result_string);
    }
    print STDERR "Done.\n";

    # Print results
    print STDERR "\nFINAL RESULTS:\n\n";
    foreach my $result_string (@results) {
        print "$result_string\n";
    }
}



sub main
{
    my $learning_dir    = '';
    my $experiment_dir  = '';

    my Readonly $usage = 'Usage: ./langid_assess.pl --learning_dir=text_to_learn_from/ '
        . '--experiment_dir=text_to_run_experiment_against/';

    GetOptions(
        'learning_dir=s'     => \$learning_dir,
        'experiment_dir=s' => \$experiment_dir,
    ) or die "$usage\n";
    die "$usage\n" unless ( $learning_dir     ne '' );
    die "$usage\n" unless ( $experiment_dir ne '' );

    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    print STDERR "starting --  " . localtime() . "\n";

    langid_assess($learning_dir, $experiment_dir);

    print STDERR "finished --  " . localtime() . "\n";


}

main();
