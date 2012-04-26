package MediaWords::Crawler::AnalyzeLines;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::Util::HTML;
use MediaWords::Crawler::Extractor;

# extract substantive new story text from html pages

use strict;
use warnings;

# don't count paragraph tags as much as others
use constant P_DISCOUNT => .1;

# don't count a tags as much as others after the first one
use constant A_DISCOUNT => .5;

# lists are bad
use constant LI_DISCOUNT => 10;

# apply discount for similarity with story description.
# set to 0 to disable
use constant DESCRIPTION_SIMILARITY_DISCOUNT => .5;

# only apply similarity test to this many characters of the story text and desciption
use constant MAX_SIMILARITY_LENGTH => 8192;

# Chinese sentences have few characters than English so count Chinese characters more
use constant CHINESE_CHARACTER_LENGTH_BONUS => 0;

# count these words as html, since they generally indicate noise words
my $_NOISE_WORDS = [
    qw/comment advertise advertisement advertising classified subscribe subscription please
      address published obituary current high low click filter select copyright reserved
      abusive defamatory post trackback url /,
    'terms of use',
    'data provided by',
    'data is provided by',
    'privacy policy',
];

#todo explain what this function really does
# return the ratio of html characters to text characters
sub get_html_density
{
    my ( $line ) = @_;

    if ( !$line )
    {
        return 1;
    }

    my $a_tag_found;
    my $html_length = 0;
    while ( $line =~ /(<\/?([a-z]*) ?[^>]*>)/g )
    {
        my ( $tag, $tag_name ) = ( $1, $2 );
        my $len = length( $1 );

        if ( lc( $tag_name ) eq 'p' )
        {
            $len *= P_DISCOUNT;
        }
        elsif ( lc( $tag_name ) eq 'li' )
        {
            $len *= LI_DISCOUNT;
        }
        elsif ( lc( $tag_name ) eq 'a' )
        {
            if ( pos( $line ) == 0 )
            {
                $len *= 2;
            }
            elsif ( pos( $line ) > 32 )
            {
                $len *= A_DISCOUNT;
            }
        }

        $html_length += $len;
    }

    for my $noise_word ( @{ $_NOISE_WORDS } )
    {
        while ( $line =~ /$noise_word/ig )
        {
            $html_length += length( $noise_word );
        }
    }

    my $chinese_character_adjustment;

    #Minor optimization -- only calculate the number of chinese character if it will affect the html density
    if ( CHINESE_CHARACTER_LENGTH_BONUS != 0 )
    {
        my $chinese_character_count = Lingua::ZH::MediaWords::number_of_Chinese_characters( $line );
        $chinese_character_adjustment = $chinese_character_count * CHINESE_CHARACTER_LENGTH_BONUS;
    }
    else
    {
        $chinese_character_adjustment = 0;
    }
    return ( $html_length / ( length( $line ) + ( $chinese_character_adjustment ) ) );
}

# return hash with lines numbers that should be included by clickprint as names:
# { linenum1 => 1, linenum2 => 1, ...}
sub get_clickprint_map
{
    my ( $markers ) = @_;

    my $clickprint_map;

    if ( !defined( $markers->{ startclickprintinclude } ) )
    {
        return;
    }

    $markers->{ endclickprintinclude }   ||= [];
    $markers->{ startclickprintexclude } ||= [];
    $markers->{ endclickprintexclude }   ||= [];

    while ( my $start_include = shift( @{ $markers->{ startclickprintinclude } } ) )
    {
        my $end_include = shift( @{ $markers->{ endclickprintinclude } } );

        if ( !defined( $end_include ) )
        {
            print STDERR
"Invalid clickprint: startclickprintinclude at line: $start_include does not have a matching endclickprintinclude";
            return;
        }

        for ( my $i = $start_include ; $i <= $end_include ; $i++ )
        {
            $clickprint_map->{ $i } = 1;
        }

        if ( my $start_exclude = shift( @{ $markers->{ startclickprintexclude } } ) )
        {
            if ( $start_exclude > $end_include )
            {
                unshift( @{ $markers->{ startclickprintexclude } }, $start_exclude );
            }
            else
            {
                my $end_exclude = shift( @{ $markers->{ endclickprintexclude } } )
                  || $end_include;

                #TODO consider just printing an error and returning of the startexclude does not have a matching end exclude

                if ( $start_exclude >= $start_include )
                {
                    for ( my $i = $start_exclude + 1 ; $i < $end_exclude ; $i++ )
                    {
                        $clickprint_map->{ $i } = 0;
                    }
                }
            }
        }
    }

    return $clickprint_map;
}

sub lineStartsWithTitleText
{
    my ( $line_text, $title_text ) = @_;

    $line_text  =~ s/[^\w .]//g;
    $title_text =~ s/[^\w .]//g;

    if ( $line_text eq $title_text )
    {

        #	print STDERR "$line_text\n";
        #	print STDERR "$title_text\n";

        return 1;
    }
    elsif ( index( $line_text, $title_text ) != -1 )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# get discount based on the similarity to the description
sub get_description_similarity_discount
{
    my ( $line, $description ) = @_;

    if ( !$description )
    {
        return 1;
    }

    if ( length( $line ) > MAX_SIMILARITY_LENGTH )
    {
        $line = substr( $line, 0, MAX_SIMILARITY_LENGTH );
    }

    if ( length( $description ) > MAX_SIMILARITY_LENGTH )
    {
        $description = substr( $description, 0, MAX_SIMILARITY_LENGTH );
    }

    my $stripped_line        = html_strip( $line );
    my $stripped_description = html_strip( $description );

    my $score =
      Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } )
      ->getSimilarityStrings( $stripped_line, $stripped_description );

    if (   ( DESCRIPTION_SIMILARITY_DISCOUNT > 1 )
        || ( DESCRIPTION_SIMILARITY_DISCOUNT < 0 ) )
    {
        die( "DESCRIPTION_SIMILARITY_DISCOUNT must be between 0 and 1" );
    }

    my $power = 1 / DESCRIPTION_SIMILARITY_DISCOUNT;

    # 1 means complete similarity and 0 means none
    # so invert it
    return ( ( 1 - $score ) )**$power;
}

#
# New subroutine "calculate_line_extraction_metrics" extracted - Mon Feb 27 17:19:53 2012.
#
sub calculate_line_extraction_metrics
{
    my $i              = shift;
    my $description    = shift;
    my $line           = shift;
    my $sphereit_map   = shift;
    my $has_clickprint = shift;

    Readonly my $article_has_clickprint => $has_clickprint;    #<--- syntax error at (eval 980) line 11, near "Readonly my "

    Readonly my $article_has_sphereit_map        => $sphereit_map;
    Readonly my $sphereit_map_includes_line      => ( $sphereit_map && $sphereit_map->{ $i } );
    Readonly my $description_similarity_discount => get_description_similarity_discount( $line, $description );

    return ( $article_has_clickprint, $article_has_sphereit_map, $description_similarity_discount,
        $sphereit_map_includes_line );
}    #<--- syntax error at (eval 980) line 18, near ";

#
# New subroutine "get_copyright_count" extracted - Mon Feb 27 17:27:56 2012.
#
sub get_copyright_count
{
    my $line = shift;

    my $copyright_count = 0;

    while ( $line =~ /copyright|copying|&copy;|all rights reserved/ig )
    {
        $copyright_count++;
    }
    return ( $copyright_count );
}

#
# New subroutine "calculate_line_extraction_metrics_2" extracted - Mon Feb 27 17:30:21 2012.
#
sub calculate_line_extraction_metrics_2
{
    my $line_text  = shift;
    my $line       = shift;
    my $title_text = shift;

    Readonly my $line_length => length( $line );    #<--- syntax error at (eval 983) line 8, near "Readonly my "
    Readonly my $line_starts_with_title_text => lineStartsWithTitleText( $line_text, $title_text );

    return ( $line_length, $line_starts_with_title_text );
}

sub calculate_full_line_metrics
{
    my ( $line, $line_number, $title_text, $description, $sphereit_map, $has_clickprint, $auto_excluded_lines, $markers ) =
      @_;

    my $line_info = {};

    $line_info->{ line_number } = $line_number;

    if (   $markers->{ comment }
        && $markers->{ comment }->[ 0 ]
        && ( $markers->{ comment }->[ 0 ] == $line_number ) )
    {
        shift( @{ $markers->{ comment } } );
        $line_info->{ has_comment } = 1;
    }
    else
    {
        $line_info->{ has_comment } = 0;
    }

    my $line_text = html_strip( $line );

    $line_info->{ html_stripped_text_length } = length( $line_text );

    if ( $auto_excluded_lines->[ $line_number ]->[ 0 ] )
    {
        my $auto_exclude_explanation = $auto_excluded_lines->[ $line_number ]->[ 1 ];

        $line_info->{ auto_excluded }            = 1;
        $line_info->{ auto_exclude_explanation } = $auto_exclude_explanation;

        return $line_info;
    }

    $line_info->{ html_density } = get_html_density( $line );

    $line_text =~ s/^\s*//;
    $line_text =~ s/\s*$//;
    $line_text =~ s/\s+/ /;

    $line_info->{ auto_excluded } = 0;

    my ( $line_length, $line_starts_with_title_text ) =
      calculate_line_extraction_metrics_2( $line_text, $line, $title_text );

    my ( $copyright_count ) = get_copyright_count( $line );

    my ( $article_has_clickprint, $article_has_sphereit_map, $description_similarity_discount, $sphereit_map_includes_line )
      = calculate_line_extraction_metrics( $line_number, $description, $line, $sphereit_map, $has_clickprint );

    $line_info->{ line_length }                     = $line_length;
    $line_info->{ line_starts_with_title_text }     = $line_starts_with_title_text;
    $line_info->{ copyright_copy }                  = $copyright_count;
    $line_info->{ article_has_clickprint }          = $article_has_clickprint;
    $line_info->{ article_has_sphereit_map }        = $article_has_sphereit_map;
    $line_info->{ description_similarity_discount } = $description_similarity_discount;
    $line_info->{ sphereit_map_includes_line }      = $sphereit_map_includes_line;

    return $line_info;
}

sub get_info_for_lines
{
    my ( $lines, $title, $description ) = @_;

    my $auto_excluded_lines = MediaWords::Crawler::Extractor::find_auto_excluded_lines( $lines );

    my $info_for_lines = [];

    my $title_text = html_strip( $title );

    $title_text =~ s/^\s*//;
    $title_text =~ s/\s*$//;
    $title_text =~ s/\s+/ /;

    my $markers        = MediaWords::Crawler::Extractor::find_markers( $lines );
    my $has_clickprint = HTML::CruftText::has_clickprint( $lines );
    my $sphereit_map   = MediaWords::Crawler::Extractor::get_sphereit_map( $markers );

    MediaWords::Crawler::Extractor::print_time( "find_markers" );

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        my $line = defined( $lines->[ $i ] ) ? $lines->[ $i ] : '';

        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        $line =~ s/\s+/ /;

        #        print STDERR "line: $line" . "\n";

        my $score;

        my ( $html_density, $discounted_html_density, $explanation );

        my $line_info = calculate_full_line_metrics( $line, $i, $title_text, $description, $sphereit_map, $has_clickprint,
            $auto_excluded_lines, $markers );

        $info_for_lines->[ $i ] = $line_info;
    }

    return $info_for_lines;
}

1;
