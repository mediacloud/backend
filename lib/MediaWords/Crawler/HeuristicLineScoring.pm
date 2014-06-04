package MediaWords::Crawler::HeuristicLineScoring;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Crawler::Extractor;

# extract substantive new story text from html pages

use strict;
use warnings;

use HTML::Entities;
use MediaWords::Util::HTML;
use Text::Similarity::Overlaps;
use Text::Trim;

use Time::HiRes;
use List::MoreUtils qw(any first_index indexes last_index none);

use Array::Compare;
use Carp qw (confess);

# lines with less than this discounted html density are extracted
use constant MAX_HTML_DENSITY => .1;

# if there are fewer than the given number of characters
# given a minimum score
use constant MINIMUM_CHARACTERS       => 32;
use constant MINIMUM_CHARACTERS_SCORE => MAX_HTML_DENSITY;

# discounts -- if a given line matches any of the following measures,
# the html density is multiplied by the given factor

# it's more likely that really long lines are substantive
use constant LENGTH_DISCOUNT_LENGTH => 256;
use constant LENGTH_DISCOUNT        => .5;

#if the line text matches the title text
use constant TITLE_MATCH_DISCOUNT => .5;

# for every mention of 'copyright' or 'copying', increase the html density
use constant COPYRIGHT_DISCOUNT => 2;

# if there are clickprintinclude tags, prefer text inside them
use constant CLICKPRINT_DISCOUNT => .25;

# if there are sphereit tags, prefer text inside them
use constant SPHEREIT_DISCOUNT => .25;

# if the line is within a few lines of an extracted line, prefer it
use constant PROXIMITY_LINES    => 1;
use constant PROXIMITY_DISCOUNT => .5;

# additions -- add some mutiple of these absolute numbers to each line

# add COMMENT_ADDITION * num of comment ids or classes before current line
use constant COMMENT_ADDITION => .02;

# add DISTANCE_ADDITION * num lines since last story line
use constant DISTANCE_ADDITION => .0001;

# requirements -- don't include the lines at all if any of these tests are met
# the discounted_html_density will be set to the large number if the condition is
# true.  make the numbers unique to be able to identify the condition

# only include lines with at least four letters
use constant REQUIRE_WORD => 1000;

# only include text from inside the body tag
use constant REQUIRE_BODY => 1001;

# if there are clickprint tags, require that the text be inside them
use constant REQUIRE_CLICKPRINT => 1002;

# if there are sphereit tags, require that the text be inside them
use constant REQUIRE_SPHEREIT => 1003;

# only include lines with non-whitespace characters
use constant REQUIRE_NON_BLANK => 1004;

# we don't care about lines with only html and no text
use constant REQUIRE_NON_HTML => 1005;

sub _score_lines_with_line_info($)
{
    my ( $info_for_lines ) = @_;

    die unless defined( $info_for_lines );

    my $scores = [];

    my $found_article_title = 0;

    my $comment_addition;

    my $last_story_line = 0;

    my $skip_title_search = none { ( $_->{ line_starts_with_title_text } ) } @{ $info_for_lines };

    for ( my $i = 0 ; $i < @{ $info_for_lines } ; $i++ )
    {
        my ( $html_density, $discounted_html_density, $explanation );

        my $line_info = $info_for_lines->[ $i ];

        if ( $line_info->{ has_comment } )
        {
            $comment_addition += COMMENT_ADDITION;
        }
        else
        {
            $comment_addition -= COMMENT_ADDITION / 40;
        }

        if ( $comment_addition < 0 )
        {
            $comment_addition = 0;
        }

        if ( $line_info->{ auto_excluded } )
        {
            my $auto_exclude_explanation = $line_info->{ auto_exclude_explanation };
            my $explanation_codes        = {
                "require body"       => REQUIRE_BODY,
                "require non-blank"  => REQUIRE_NON_BLANK,
                "require non-html"   => REQUIRE_NON_HTML,
                "require word"       => REQUIRE_WORD,
                "require clickprint" => REQUIRE_CLICKPRINT,
                "require sphereit"   => REQUIRE_SPHEREIT
            };

            $discounted_html_density = $explanation_codes->{ $auto_exclude_explanation }
              || confess "Invalid explanation: $auto_exclude_explanation";

            $explanation .= "$auto_exclude_explanation\n";
        }
        else
        {

            $html_density = $line_info->{ html_density };

            if (   ( $line_info->{ line_length } < MINIMUM_CHARACTERS )
                && ( $line_info->{ html_density } < MINIMUM_CHARACTERS_SCORE ) )
            {
                $explanation .= "minimum characters score: " . MINIMUM_CHARACTERS_SCORE . "\n";
                $line_info->{ html_density } = MINIMUM_CHARACTERS_SCORE;
            }

            $discounted_html_density = $line_info->{ html_density };

            if ( !$skip_title_search )
            {
                if ( $line_info->{ line_starts_with_title_text } )
                {
                    $found_article_title = 1;
                    $explanation .= "title match discount" . "\n";
                    $discounted_html_density *= TITLE_MATCH_DISCOUNT;
                }

                if ( !$found_article_title )
                {
                    $explanation .= "per-title addition \n";
                    $discounted_html_density += .1;
                }
            }

            if ( $comment_addition )
            {
                $explanation .= "comment addition: $comment_addition\n";
                $discounted_html_density += $comment_addition;
            }

            if ( $line_info->{ line_length } > LENGTH_DISCOUNT_LENGTH )
            {
                $explanation .= "length discount: " . LENGTH_DISCOUNT . "\n";
                $discounted_html_density *= LENGTH_DISCOUNT;
            }
            if ( $line_info->{ line_length } > ( 4 * LENGTH_DISCOUNT_LENGTH ) )
            {
                $explanation .= "super length discount: " . LENGTH_DISCOUNT . "\n";
                $discounted_html_density *= LENGTH_DISCOUNT;
            }

            for ( my $j = 0 ; $j < $line_info->{ copyright_copy } ; $j++ )
            {
                $explanation .= "copyright discount: " . COPYRIGHT_DISCOUNT . "\n";
                $discounted_html_density *= COPYRIGHT_DISCOUNT;
            }

            if ( $line_info->{ article_has_clickprint } )
            {
                $explanation .= "clickprint discount: " . CLICKPRINT_DISCOUNT . "\n";
                $discounted_html_density *= CLICKPRINT_DISCOUNT;
            }

            if ( $line_info->{ article_has_sphereit_map } && $line_info->{ sphereit_map_includes_line } )
            {
                $explanation .= "sphereit discount: " . SPHEREIT_DISCOUNT . "\n";
                $discounted_html_density *= SPHEREIT_DISCOUNT;
            }

            if ( $last_story_line )
            {
                my $distance_to_last_story_line = $i - $last_story_line;
                if ( $distance_to_last_story_line
                    && ( $distance_to_last_story_line <= PROXIMITY_LINES ) )
                {
                    $explanation .= "proximity discount: " . PROXIMITY_DISCOUNT . "\n";
                    $discounted_html_density *= PROXIMITY_DISCOUNT;
                }
                else
                {
                    my $a = ( $distance_to_last_story_line * DISTANCE_ADDITION );
                    $explanation .= "distance addition: $a\n";
                    $discounted_html_density += $a;
                }
            }

            if (   ( $discounted_html_density > MAX_HTML_DENSITY )
                && ( $discounted_html_density < ( MAX_HTML_DENSITY * 3 ) ) )
            {
                my $d = $line_info->{ description_similarity_discount };
                if ( $d < 1 )
                {
                    $explanation .= "similarity discount: $d\n";
                }
                $discounted_html_density *= $d;
            }
        }

        my $score;
        $score->{ html_density }            = $html_density                                   || 0;
        $score->{ discounted_html_density } = $discounted_html_density                        || 0;
        $score->{ explanation }             = $explanation                                    || '';
        $score->{ is_story }                = ( $discounted_html_density < MAX_HTML_DENSITY ) || 0;
        $score->{ line_number }             = $i;

        my $include_probability;

        if ( $discounted_html_density < MAX_HTML_DENSITY )
        {
            $include_probability = 1 - ( $discounted_html_density / MAX_HTML_DENSITY ) * 0.5;
        }
        else
        {
            $include_probability = 0.5 * ( MAX_HTML_DENSITY / $discounted_html_density );
        }

        $score->{ include_probability } = $include_probability;

        if ( $score->{ is_story } )
        {
            $last_story_line = $i;
        }

        if ( $score->{ is_story } )
        {
            if ( $line_info->{ line_starts_with_title_text } )
            {
                $score->{ predicted_class } = 'optional';
            }
            else
            {
                $score->{ predicted_class } = 'required';
            }

            die Dumper( $line_info ) if $explanation =~ /title/;
        }
        else
        {
            $score->{ predicted_class } = 'excluded';
        }

        # print "score: [" . $score->{is_story} . " / " . $score->{html_density} . "] $line\n";

        push( @{ $scores }, $score );
    }

    MediaWords::Crawler::Extractor::print_time( "loop_lines" );

    die "Did not find title text" if ( !$found_article_title && !$skip_title_search );

    return $scores;
}

1;
