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

# CONSTANTS

# only include lines with at least four letters
use constant REQUIRE_WORD => 1000;

# if there are clickprint tags, require that the text be inside them
use constant REQUIRE_CLICKPRINT => 1002;

# if there are sphereit tags, require that the text be inside them
use constant REQUIRE_SPHEREIT => 1003;

# only include lines with non-whitespace characters
use constant REQUIRE_NON_BLANK => 1004;

# we don't care about lines with only html and no text
use constant REQUIRE_NON_HTML => 1005;

# STATICS

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

# return hash with lines numbers that should be included by sphereit
# { linenum1 => 1, linenum2 => 1, ...}
sub get_sphereit_map($$)
{
    my ( $markers, $language_code ) = @_;

    my $sphereit_map;
    while ( my $start = shift( @{ $markers->{ sphereitbegin } } ) )
    {
        my $end = shift( @{ $markers->{ sphereitend } } ) || $start;

        for ( my $i = $start ; $i <= $end ; $i++ )
        {
            $sphereit_map->{ $i } = 1;
        }
    }

    return $sphereit_map;
}

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

sub find_auto_excluded_lines($$;$)
{
    my ( $lines, $language_code, $markers ) = @_;

    unless ( $markers )
    {
        $markers = find_markers( $lines, $language_code );
    }
    my $sphereit_map = get_sphereit_map( $markers, $language_code );

    my $ret = [];

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        my $line = defined( $lines->[ $i ] ) ? $lines->[ $i ] : '';

        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        $line =~ s/\s+/ /;

        my $explanation;

        my $auto_exclude = 0;

        if ( $markers->{ body }
            && ( $i < ( $markers->{ body }->[ 0 ] || 0 ) ) )
        {
            $explanation .= "require body";
            $auto_exclude = 1;
        }
        elsif ( REQUIRE_NON_BLANK && ( $line =~ /^\s*$/ ) )
        {
            $explanation .= "require non-blank";
            $auto_exclude = 1;
        }
        elsif ( REQUIRE_NON_HTML && MediaWords::Util::HTML::html_strip( $line ) !~ /[\w]/i )
        {
            $explanation .= "require non-html";
            $auto_exclude = 1;
        }
        elsif ( REQUIRE_WORD && ( decode_entities( $line ) !~ /\w{4}/i ) )
        {
            $explanation .= "require word";
            $auto_exclude = 1;
        }
        elsif ( REQUIRE_SPHEREIT && $sphereit_map && !$sphereit_map->{ $i } )
        {
            $explanation .= "require sphereit";
            $auto_exclude = 1;
        }

        if ( $auto_exclude )
        {
            $ret->[ $i ] = [ 1, $explanation ];
        }
        else
        {
            $ret->[ $i ] = [ 0 ];
        }
    }

    return $ret;
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
