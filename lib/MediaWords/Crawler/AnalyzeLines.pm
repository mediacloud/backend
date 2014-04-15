package MediaWords::Crawler::AnalyzeLines;

use List::MoreUtils qw( uniq distinct :all );
use List::Util qw( sum  );
use Text::Trim;

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::HTML;
use MediaWords::Util::Text;
use MediaWords::Crawler::Extractor;
use MediaWords::Languages::Language;
use MediaWords::Util::IdentifyLanguage;
use Carp;
use HTML::Entities;
use Set::Jaccard::SimilarityCoefficient;

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

#todo explain what this function really does
# return the ratio of html characters to text characters
sub _get_html_density($$)
{
    my ( $line, $language_code ) = @_;

    if ( !$line )
    {
        return 1;
    }

    my $a_tag_found;
    my $html_length = 0;
    while ( $line =~ /(<\/?([a-z]*) ?[^>]*>)/g )
    {
        my ( $len, $tag_name ) = ( length( $1 ), lc( $2 ) );

        if ( $tag_name eq 'p' )
        {
            $len *= P_DISCOUNT;
        }
        elsif ( $tag_name eq 'li' )
        {
            $len *= LI_DISCOUNT;
        }
        elsif ( $tag_name eq 'a' )
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

    # Noise words
    # (count these words as html, since they generally indicate noise words)
    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    unless ( $lang )
    {
        die "Language is null for language code '$language_code'.\n";
    }
    my $noise_strings_regex = $lang->get_noise_strings_regex();
    unless ( $noise_strings_regex )
    {
        die "Noise strings regular expression is null for language code '$language_code'.\n";
    }

    my @noise_strings_matches = ( $line =~ /$noise_strings_regex/g );
    map { $html_length += length( $_ ) } @noise_strings_matches;

    return ( $html_length / ( length( $line ) ) );
}

sub _lineStartsWithTitleText($$)
{
    my ( $line_text, $title_text ) = @_;

    $line_text =~ s/[^\w .]//g;
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
sub _get_description_similarity_discount($$$)
{
    my ( $line, $description, $language_code ) = @_;

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

    my $score = MediaWords::Util::Text::get_similarity_score( $stripped_line, $stripped_description, $language_code );

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

# get discount based on the similarity to the description
sub _get_description_jaccard($$)
{
    my ( $description, $line ) = @_;

    if ( !$description )
    {
        return 0;
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

    my $line_words = words_on_line( $stripped_line );
    my $description_words = words_on_line( $stripped_description );

    if ( scalar( @$line_words) <= 0 && scalar( @$description_words) <= 0 )
    {
	return 0;
    }

    return Set::Jaccard::SimilarityCoefficient::calc( $line_words, $description_words );
}

#
# New subroutine "_calculate_line_extraction_metrics" extracted - Mon Feb 27 17:19:53 2012.
#
sub _calculate_line_extraction_metrics($$$$$$)
{
    my ( $i, $description, $line, $sphereit_map, $has_clickprint, $language_code ) = @_;

    my $article_has_clickprint = $has_clickprint;

    my $article_has_sphereit_map        = defined( $sphereit_map );
    my $sphereit_map_includes_line      = ( defined( $sphereit_map ) && $sphereit_map->{ $i } );
    my $description_similarity_discount = _get_description_similarity_discount( $line, $description, $language_code );

    return ( $article_has_clickprint, $article_has_sphereit_map, $description_similarity_discount,
        $sphereit_map_includes_line );
}

#
# New subroutine "get_copyright_count" extracted - Mon Feb 27 17:27:56 2012.
#
sub _get_copyright_count($$)
{
    my ( $line, $language_code ) = @_;

    my $copyright_count = 0;

    # Copyright strings
    my $lang              = MediaWords::Languages::Language::language_for_code( $language_code );
    my $copyright_strings = $lang->get_copyright_strings();

    for my $copyright_string ( @{ $copyright_strings } )
    {
        while ( $line =~ /$copyright_string/ig )
        {
            $copyright_count++;
        }
    }

    return ( $copyright_count );
}

#
# New subroutine "_calculate_line_extraction_metrics_2" extracted - Mon Feb 27 17:30:21 2012.
#
sub _calculate_line_extraction_metrics_2($$$$)
{
    my ( $line_text, $line, $title_text, $language_code ) = @_;

    my $line_length = length( $line );
    my $line_starts_with_title_text = _lineStartsWithTitleText( $line_text, $title_text );

    return ( $line_length, $line_starts_with_title_text );
}

sub _calculate_full_line_metrics($$$$$$$$$)
{
    my (
        $line,           $line_number,         $title_text, $description, $sphereit_map,
        $has_clickprint, $auto_excluded_lines, $markers,    $language_code
    ) = @_;

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

    $line_info->{ html_density } = _get_html_density( $line, $language_code );

    $line_text =~ s/^\s*//;
    $line_text =~ s/\s*$//;
    $line_text =~ s/\s+/ /;

    $line_info->{ auto_excluded } = 0;

    my ( $line_length, $line_starts_with_title_text ) =
      _calculate_line_extraction_metrics_2( $line_text, $line, $title_text, $language_code );

    my ( $copyright_count ) = _get_copyright_count( $line, $language_code );

    my ( $article_has_clickprint, $article_has_sphereit_map, $description_similarity_discount, $sphereit_map_includes_line )
      = _calculate_line_extraction_metrics( $line_number, $description, $line, $sphereit_map, $has_clickprint,
        $language_code );

    my $description_jaccard  = _get_description_jaccard( $description, $line );

    $line_info->{ line_length }                     = $line_length;
    $line_info->{ line_starts_with_title_text }     = $line_starts_with_title_text;
    $line_info->{ copyright_copy }                  = $copyright_count;
    $line_info->{ article_has_clickprint }          = $article_has_clickprint;
    $line_info->{ article_has_sphereit_map }        = $article_has_sphereit_map;
    $line_info->{ description_similarity_discount } = $description_similarity_discount;
    
    $line_info->{ description_jaccard } = $description_jaccard;

    $line_info->{ sphereit_map_includes_line }      = $sphereit_map_includes_line;

    return $line_info;
}

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

# find various markers that can be used to discount line scores
# return a hash of the found markers
sub _find_markers($$)
{
    my ( $lines, $language_code ) = @_;

    my $markers = {};

    while ( my ( $name, $pattern ) = each( %{ $_MARKER_PATTERNS } ) )
    {
        $markers->{ $name } = [ indexes { $_ =~ $pattern } @{ $lines } ];
    }

    return $markers;
}


# return hash with lines numbers that should be included by sphereit
# { linenum1 => 1, linenum2 => 1, ...}
sub _get_sphereit_map($$)
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

sub _find_auto_excluded_lines($$;$)
{
    my ( $lines, $language_code, $markers ) = @_;

    unless ( $markers )
    {
        $markers = find_markers( $lines, $language_code );
    }
    my $sphereit_map = _get_sphereit_map( $markers, $language_code );

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
        elsif ( $line =~ /^\s*$/ )
        {
            $explanation .= "require non-blank";
            $auto_exclude = 1;
        }
        elsif ( MediaWords::Util::HTML::html_strip( $line ) !~ /[\w]/i )
        {
            $explanation .= "require non-html";
            $auto_exclude = 1;
        }
        elsif ( decode_entities( $line ) !~ /\w{4}/i )
        {
            $explanation .= "require word";
            $auto_exclude = 1;
        }
        elsif ( $sphereit_map && !$sphereit_map->{ $i } )
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

sub get_info_for_lines($$$)
{
    my ( $lines, $title, $description ) = @_;

    # Story language will be later determined in MediaWords::StoryVectors too,
    # but before that let's take into account a full HTML page (because presumably)
    # even if the story is written in language B, the page itself (including the
    # copyright lines and such) will still be present in language A.
    my $full_text = join( "\n", @{ $lines } );
    my $language_code = MediaWords::Util::IdentifyLanguage::language_code_for_text( $full_text, undef, 1 );
    unless ( MediaWords::Languages::Language::language_for_code( $language_code ) )
    {

        # Unknown language, fallback to English
        $language_code = MediaWords::Languages::Language::default_language_code();
        say STDERR "Language for the story '$title' was not determined / enabled," .
          " falling back to default language '$language_code'.";
    }

    my $markers = _find_markers( $lines, $language_code );
    my $auto_excluded_lines = _find_auto_excluded_lines( $lines, $language_code, $markers );
    my $has_clickprint      = HTML::CruftText::has_clickprint( $lines );
    my $sphereit_map        = _get_sphereit_map( $markers, $language_code );

    my $info_for_lines = [];

    my $title_text = html_strip( $title );

    $title_text =~ s/^\s*//;
    $title_text =~ s/\s*$//;
    $title_text =~ s/\s+/ /;

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        my $line = defined( $lines->[ $i ] ) ? $lines->[ $i ] : '';

        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        $line =~ s/\s+/ /;

        #        print STDERR "line: $line" . "\n";

        my $score;

        my ( $html_density, $discounted_html_density, $explanation );

        my $line_info = _calculate_full_line_metrics(
            $line,           $i,                   $title_text, $description, $sphereit_map,
            $has_clickprint, $auto_excluded_lines, $markers,    $language_code
        );

        $info_for_lines->[ $i ] = $line_info;
    }

    return $info_for_lines;
}

sub words_on_line($)
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

sub add_additional_features($$)
{
    my ( $line_info, $line_text ) = @_;

    my $plain_text = html_strip( $line_text );
    my $words = [ split /\s+/, $plain_text ];

    my $num_words = scalar( @{ $words } );

    return if $num_words == 0;

    my $num_links = ( $line_text =~ /<a / );

    $line_info->{ links } = $num_links;
    if ( $num_links > 0 )
    {
        $line_info->{ link_word_ratio } = $num_words / $num_links;
    }

    $line_info->{ num_words } = $num_words;

    my $word_characters_total_length = sum( map { length( $_ ) } @{ $words } );

    $line_info->{ avg_word_length } = $word_characters_total_length / $num_words;

    my $upper_case_words = [ grep { ucfirst( $_ ) eq $_ } @{ $words } ];

    my $num_uppercase = scalar( @{ $upper_case_words } );

    my $uppercase_ratio = $num_uppercase / $num_words;

    $line_info->{ num_uppercase }   = $num_uppercase;
    $line_info->{ uppercase_ratio } = $uppercase_ratio;

    return;
}

my $banned_fields;

sub get_feature_string_from_line_info($$;$)
{
    my ( $line_info, $line_text, $top_words ) = @_;

    #say Dumper( $line_info );

    my @feature_fields = sort ( keys %{ $line_info } );

    my $ret = '';

    #say STDERR join "\n", @feature_fields;

    if ( !defined( $banned_fields ) )
    {
        my @banned_fields = qw ( line_number auto_excluded auto_exclude_explanation copyright_copy );

        $banned_fields = {};

        foreach my $banned_field ( @banned_fields )
        {
            $banned_fields->{ $banned_field } = 1;
        }
    }

    foreach my $feature_field ( @feature_fields )
    {
        next if defined( $banned_fields->{ $feature_field } );

        next if $feature_field eq 'class';

        next unless ( defined( $line_info->{ $feature_field } ) );
        next if ( $line_info->{ $feature_field } eq '0' );
        next if ( $line_info->{ $feature_field } eq '' );

        my $field_value = $line_info->{ $feature_field };

        if ( $field_value eq '1' )
        {
            $ret .= $feature_field;
            $ret .= '=' . $field_value;    # || 0;
            $ret .= ' ';
        }
        else
        {
            my $val = 1.0;

            #say STDERR $field_value;

            my $last_feature = '';
            while ( $field_value < $val )
            {
                $last_feature = $feature_field . '_lt_' . $val;
                $val /= 2;
            }

            $val = 1.0;

            while ( $field_value > $val )
            {
                $last_feature = $feature_field . '_gt_' . $val;
                $val *= 2;
            }

            die if $last_feature eq '';
            $ret .= $last_feature . ' ';
        }

    }

    my $words = words_on_line( $line_text );

    foreach my $word ( @{ $words } )
    {

        next if ( defined( $top_words ) && ( !$top_words->{ $word } ) );

        $ret .= 'unigram_' . $word . ' ';
    }

    if ( defined( $line_info->{ class } ) )
    {
        $ret .= $line_info->{ class };
    }

    return $ret;
}

sub _mark_auto_excluded_previous_lines
{
    my ( $line_infos ) = ( @_ );

    my $previous_line_auto_excluded = 0;
    foreach my $line_info ( @{ $line_infos } )
    {
        if ( $previous_line_auto_excluded )
        {
            $line_info->{ previous_line_auto_excluded } = 1;
        }

        $previous_line_auto_excluded = $line_info->{ auto_excluded };
    }

    return;
}

sub get_feature_strings_for_download
{
    my ( $line_infos, $preprocessed_lines, $top_words ) = @_;

    confess unless defined( $line_infos ) and defined( $preprocessed_lines );

    my $ret = [];

    _mark_auto_excluded_previous_lines( $line_infos );

    my $ea = each_arrayref( $line_infos, $preprocessed_lines );

    #TODO DRY out this code
    while ( my ( $line_info, $line_text ) = $ea->() )
    {
        my $current_state = $line_info->{ class };

        if ( $line_info->{ auto_excluded } == 1 )
        {
            $current_state = 'auto_excluded';
        }

        next if $line_info->{ auto_excluded } == 1;

        MediaWords::Crawler::AnalyzeLines::add_additional_features( $line_info, $line_text );

        my $feature_string =
          MediaWords::Crawler::AnalyzeLines::get_feature_string_from_line_info( $line_info, $line_text, $top_words );
        push $ret, $feature_string;
    }

    return $ret;
}

1;
