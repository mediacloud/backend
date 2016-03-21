package MediaWords::Crawler::Extractor;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

# extract substantive new story text from html pages

# this code is the implementation of our old custom extractor, which we refer to as the 'Heuristic Extractor' in
# various places.  we still allow the user to choose to use this extractor by setting mediawords.extract_method
# to HeuristicExtractor in mediawords.yml.  but the production always uses the PythonReadability server.

# we keep this around mostly so that we can allow instances of Media Cloud to do extraction without having to run
# the thrift python readability extractor, but we should replace this with a version of the python readability
# extractor that just calls the readability extractor inline (which is simple but slower than using the web service).

use strict;

use HTML::Entities;
use MediaWords::Util::HTML;
use MediaWords::Crawler::HeuristicLineScoring;
use MediaWords::Crawler::AnalyzeLines;
use Text::Similarity::Overlaps;
use Text::Trim;

use Time::HiRes;
use List::MoreUtils qw(first_index indexes last_index);
use Array::Compare;
use HTML::CruftText 0.02;
use Carp qw (confess);

# METHODS

sub preprocess
{
    return HTML::CruftText::clearCruftText( @_ );
}

my $_start_time;
my $_last_time;

sub print_time
{
    my ( $s ) = @_;

    return;

    my $t = Time::HiRes::gettimeofday();
    $_start_time ||= $t;
    $_last_time  ||= $t;

    my $elapsed     = $t - $_start_time;
    my $incremental = $t - $_last_time;

    printf( STDERR "time $s: %f elapsed %f incremental\n", $elapsed, $incremental );

    $_last_time = $t;
}

# given a reference to an html story (news, blog, etc), return just the substantive text.
# uses text to html density along with a variety of other metrics to pick substantive
# content vs. ads, navigation, and other affluvia
sub score_lines($$$)
{
    my ( $lines, $title, $description ) = @_;

    return heuristically_scored_lines( $lines, $title, $description );
}

sub heuristically_scored_lines($$$)
{
    my ( $lines, $title, $description ) = @_;

    return _heuristically_scored_lines_impl( $lines, $title, $description );
}

sub _heuristically_scored_lines_impl($$$)
{
    my ( $lines, $title, $description ) = @_;

    # use Data::Dumper;
    # die ( Dumper( @_ ) );

    print_time( "score_lines" );

    if ( !defined( $lines ) )
    {
        return;
    }

    my $info_for_lines = MediaWords::Crawler::AnalyzeLines::get_info_for_lines( $lines, $title, $description );

    my $scores = MediaWords::Crawler::HeuristicLineScoring::_score_lines_with_line_info( $info_for_lines );

    return $scores;
}

1;
