package HTML::CruftText;

# extract substantive new story text from html pages

use strict;
use warnings;

use HTML::Entities;
use Text::Similarity::Overlaps;
use Time::HiRes;
use List::MoreUtils qw(first_index indexes last_index);
use Array::Compare;

# STATICS

# markers -- patterns used to find lines than can help find the text
my $_MARKER_PATTERNS = {
    startclickprintinclude => qr/<\!--\s*startclickprintinclude/pi,
    endclickprintinclude   => qr/<\!--\s*endclickprintinclude/pi,
    startclickprintexclude => qr/<\!--\s*startclickprintexclude/pi,
    endclickprintexclude   => qr/<\!--\s*endclickprintexclude/pi,
    sphereitbegin          => qr/<\!--\s*DISABLEsphereit\s*start/i,
    sphereitend            => qr/<\!--\s*DISABLEsphereit\s*end/i,
    body                   => qr/<body/i,
    comment                => qr/(id|class)="[^"]*comment[^"]*"/i,
};

#TODO handle sphereit like we're now handling CLickprint.

# blank everything within these elements
my $_SCRUB_TAGS = [ qw/script style frame applet textarea/ ];

# METHODS

#
# TODO rewrite _remove_tags_in_comments using Inline::C to improve performance.
#

# remove >s from inside comments so the simple line density scorer
# doesn't get confused about where tags end
sub _remove_tags_in_comments
{
    my ( $lines ) = @_;

    my $state = 'text';

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        my $line = \$lines->[ $i ];

        my $pos    = 0;
        my $length = length( $$line );
        while ( $pos < $length )
        {

            #print "state $i $pos: $state\n";
            if ( $state eq 'text' )
            {
                if ( substr( $$line, $pos, 2 ) eq '<!' )
                {
                    $state = 'declaration';
                    $pos += 2;
                }
                else
                {
                    $pos++;
                }
            }
            elsif ( $state eq 'declaration' )
            {
                if ( substr( $$line, $pos, 2 ) eq '--' )
                {
                    $state = 'comment';
                    $pos += 2;

                    my $extra_hyphens = 0;

                    # deal with commonly broken comment syntax
                    while ( substr( $$line, $pos, 1 ) eq '-' )
                    {
                        $pos++;
                        $extra_hyphens++;
                    }

                    #deal with empty comment <!---->
                    if ( ( $extra_hyphens >= 2 ) && ( substr( $$line, $pos, 1 ) eq '>' ) )
                    {
                        $state = 'declaration';
                    }
                }
                elsif ( substr( $$line, $pos, 1 ) eq '>' )
                {
                    $state = 'text';
                    $pos += 1;
                }
                else
                {
                    $pos++;
                }
            }
            elsif ( $state eq 'comment' )
            {
                if (   ( substr( $$line, $pos, 1 ) eq '<' )
                    || ( substr( $$line, $pos, 1 ) eq '>' ) )
                {
                    substr( $lines->[ $i ], $pos, 1 ) = '|';
                    $pos += 1;
                }
                elsif ( substr( $$line, $pos, 2 ) eq '--' )
                {
                    $pos += 2;

                    # deal with commonly broken comment syntax
                    while ( substr( $$line, $pos, 1 ) eq '-' )
                    {
                        $pos++;
                    }

                    if ( substr( $$line, $pos, 1 ) eq '>' )
                    {
                        $state = 'declaration';
                    }
                    else
                    {    # Handle the case of a comment with ---- in the middle of it e.g. <!-- -------- -->
                        $state = 'comment';
                    }

                }
                else
                {
                    $pos++;
                }
            }
        }    #while ( $pos < $length )

        if ( $state eq 'comment' )
        {
            $lines->[ $i ] .= ' -->';
            if ( defined( $lines->[ $i + 1 ] ) )
            {
                $lines->[ $i + 1 ] = '<!-- ' . $lines->[ $i + 1 ];
                $state = 'text';
            }
        }
        elsif ( $state eq 'declaration' )
        {
            $lines->[ $i ] .= ' >';
            if ( defined( $lines->[ $i + 1 ] ) )
            {
                $lines->[ $i + 1 ] = '<!DECLARATION ' . $lines->[ $i + 1 ];
                $state = 'text';
            }
        }
    }    # for
}

# make sure that all tags start and close on one line
# by adding false <>s as necessary, eg:
#
# <foo
# bar>
#
# becomes
#
# <foo>
# <tag bar>
#
sub _fix_multiline_tags
{
    my ( $lines ) = @_;

    my $add_start_tag;
    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        if ( $add_start_tag )
        {
            $lines->[ $i ] = "<$add_start_tag " . $lines->[ $i ];
            $add_start_tag = undef;
        }

        if ( $lines->[ $i ] =~ /<([^ >]*)[^>]*$/ )
        {
            $add_start_tag = $1;
            $lines->[ $i ] .= ' >';
        }
    }
}

#remove all text not within the <body> tag
#Note: Some badly formated web pages will have multiple <body> tags or will not have an open tag.
#We go the conservative thing of only deleting stuff before the first <body> tag and stuff after the last </body> tag.
sub _remove_nonbody_text
{
    my ( $lines ) = @_;

    my $add_start_tag;

    my $state = 'before_body';

    my $body_open_tag_line_number = first_index { $_ =~ /<body/i } @{ $lines };

    if ( $body_open_tag_line_number != -1 )
    {

        #delete everything before <body>
        for ( my $line_number_to_clear = 0 ; $line_number_to_clear < $body_open_tag_line_number ; $line_number_to_clear++ )
        {
            $lines->[ $line_number_to_clear ] = '';
        }

        $lines->[ $body_open_tag_line_number ] =~ s/^.*?\<body/<body/i;
    }

    my $body_close_tag_line_number = last_index { $_ =~ /<\/body/i } @{ $lines };

    if ( $body_close_tag_line_number != -1 )
    {

        #delete everything after </body>

        $lines->[ $body_close_tag_line_number ] =~ s/<\/body>.*/<\/body>/i;
        for (
            my $line_number_to_clear = ( $body_close_tag_line_number + 1 ) ;
            $line_number_to_clear < scalar( @{ $lines } ) ;
            $line_number_to_clear++
          )
        {
            $lines->[ $line_number_to_clear ] = '';
        }
    }
}

sub has_clickprint
{
    my ( $lines ) = @_;

    return defined( _clickprint_start_line( $lines ) );
}

sub _clickprint_start_line
{
    my ( $lines ) = @_;

    my $i = 0;

    my $found_clickprint = 0;

    while ( ( $i < @{ $lines } ) && !$found_clickprint )
    {
        if ( $lines->[ $i ] =~ $_MARKER_PATTERNS->{ startclickprintinclude } )
        {
            $found_clickprint = 1;
        }
        else
        {
            $i++;
        }
    }

    if ( !$found_clickprint )
    {
        return;
    }
    else
    {
        return $i;

    }
}

sub _remove_nonclickprint_text
{
    my ( $lines, $clickprintmap ) = @_;

    my $clickprint_start_line = _clickprint_start_line( $lines );

    return if !defined( $clickprint_start_line );

    # blank out all line before the first click_print

    for ( my $j = 0 ; $j < $clickprint_start_line ; $j++ )
    {
        $lines->[ $j ] = '';
    }

    my $i = $clickprint_start_line;

    my $current_substring = \$lines->[ $i ];
    my $state             = "before_clickprint";

    while ( $i < @{ $lines } )
    {

        #		print
        #		  "i = $i state = $state current_substring = $$current_substring \n";

        if ( $state eq "before_clickprint" )
        {
            if ( $$current_substring =~ $_MARKER_PATTERNS->{ startclickprintinclude } )
            {
                $$current_substring =~
                  "s/.*?$_MARKER_PATTERNS->{startclickprintinclude}/$_MARKER_PATTERNS->{startclickprintinclude}/p";

                $$current_substring =~ $_MARKER_PATTERNS->{ startclickprintinclude };

                $current_substring = \substr( $$current_substring, length( ${^PREMATCH} ) + length( ${^MATCH} ) );

                $current_substring = \_get_string_after_comment_end_tags( $current_substring );

                $state = "in_click_print";
            }
            else
            {
                $$current_substring = '';
            }
        }

        if ( $state eq 'in_click_print' )
        {

            #			print "in_click_print\n";
            if ( $$current_substring =~ $_MARKER_PATTERNS->{ startclickprintexclude } )
            {
                $current_substring = \substr( $$current_substring, length( ${^MATCH} ) + length( ${^PREMATCH} ) );

                $current_substring = \_get_string_after_comment_end_tags( $current_substring );
                $state             = "in_click_print_exclude";

            }
            elsif ( $$current_substring =~ $_MARKER_PATTERNS->{ endclickprintinclude } )
            {
                $current_substring = \substr( $$current_substring, length( ${^MATCH} ) + length( ${^PREMATCH} ) );

                $current_substring = \_get_string_after_comment_end_tags( $current_substring );

                $state = 'before_clickprint';
                next;
            }
        }

        if ( $state eq 'in_click_print_exclude' )
        {
            if ( $$current_substring =~ $_MARKER_PATTERNS->{ endclickprintexclude } )
            {
                my $index = index( $$current_substring, $_MARKER_PATTERNS->{ endclickprintexclude } );

                substr( $$current_substring, 0, length( ${^PREMATCH} ), '' );

                $current_substring = \substr( $$current_substring, length( ${^MATCH} ) );

                $current_substring = \_get_string_after_comment_end_tags( $current_substring );

                $state = "in_click_print";
                next;
            }
            else
            {
                $$current_substring = '';
            }
        }

        $i++;
        if ( $i < @{ $lines } )
        {
            $current_substring = \$lines->[ $i ];
        }
    }
}

sub _get_string_after_comment_end_tags
{
    my ( $current_substring, $i ) = @_;

    my $comment_end_pos = 0;

    if ( $$current_substring =~ /^\s*-->/p )
    {
        $comment_end_pos = length( ${^MATCH} );
    }
    return substr( $$current_substring, $comment_end_pos );
}

# remove text wthin script, style, iframe, applet, and textarea tags
sub _remove_script_text
{
    my ( $lines ) = @_;

    my $state = 'text';
    my $start_scrub_tag_name;

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        my $line = $lines->[ $i ];

        #print "line $i: $line\n";
        my @scrubs;
        my $start_scrub_pos = 0;
        while ( $line =~ /(<(\/?[a-z]+)[^>]*>)/gi )
        {
            my $tag      = $1;
            my $tag_name = $2;

            #print "found tag $tag_name\n";
            if ( $state eq 'text' )
            {
                if ( grep { lc( $tag_name ) eq $_ } @{ $_SCRUB_TAGS } )
                {

                    #print "found scrub tag\n";
                    $state                = 'scrub_text';
                    $start_scrub_pos      = pos( $line );
                    $start_scrub_tag_name = $tag_name;
                }
            }
            elsif ( $state eq 'scrub_text' )
            {
                if ( lc( $tag_name ) eq lc( "/$start_scrub_tag_name" ) )
                {
                    $state = 'text';
                    my $end_scrub_pos = pos( $line ) - length( $tag );

                    # delay actual scrubbing of text until the end so that we don't
                    # have to reset the position of the state machine
                    push( @scrubs, [ $start_scrub_pos, $end_scrub_pos - $start_scrub_pos ] );
                }
            }
        }

        if ( $state eq 'scrub_text' )
        {
            push( @scrubs, [ $start_scrub_pos, length( $line ) - $start_scrub_pos ] );
        }

        my $scrubbed_length = 0;
        for my $scrub ( @scrubs )
        {

            #print "scrub line $i\n";
            substr( $lines->[ $i ], $scrub->[ 0 ] - $scrubbed_length, $scrub->[ 1 ] ) = '';
            $scrubbed_length += $scrub->[ 1 ];
        }

        #print "scrubbed line: $lines->[$i]\n";
    }
}

sub clearCruftText
{
    my $lines = shift;

    if ( !ref( $lines ) )
    {
        $lines = [ split( /[\n\r]+/, $lines ) ];
    }

    print_time( "split_lines" );

    _remove_tags_in_comments( $lines );
    print_time( "remove tags" );
    _fix_multiline_tags( $lines );
    print_time( "fix multiline" );
    _remove_script_text( $lines );
    print_time( "remove scripts" );
    _remove_nonbody_text( $lines );
    print_time( "remove nonbody" );
    _remove_nonclickprint_text( $lines );
    print_time( "remove clickprint" );

    return $lines;
}

my $_start_time;
my $_last_time;

sub print_time
{
    return;

    my ( $s ) = @_;

    my $t = Time::HiRes::gettimeofday();
    $_start_time ||= $t;
    $_last_time  ||= $t;

    my $elapsed     = $t - $_start_time;
    my $incremental = $t - $_last_time;

    printf( STDERR "time $s: %f elapsed %f incremental\n", $elapsed, $incremental );

    $_last_time = $t;
}

1;
