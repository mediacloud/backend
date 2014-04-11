package MediaWords::Crawler::Extractor;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# extract substantive new story text from html pages

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

## TODO merge this with the one in HTML::CruftText
# markers -- patterns used to find lines than can help find the text
my $_MARKER_PATTERNS = {
    startclickprintinclude => qr/<\!--\s*startclickprintinclude/i,
    endclickprintinclude   => qr/<\!--\s*endclickprintinclude/i,
    startclickprintexclude => qr/<\!--\s*startclickprintexclude/i,
    endclickprintexclude   => qr/<\!--\s*endclickprintexclude/i,
    sphereitbegin          => qr/<\!--\s*DISABLEsphereit\s*start/i,
    sphereitend            => qr/<\!--\s*DISABLEsphereit\s*end/i,
    body                   => qr/<body/i,
    comment                => qr/(id|class)="[^"]*comment[^"]*"/i,
};

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
