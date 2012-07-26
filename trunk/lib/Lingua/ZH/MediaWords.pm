package Lingua::ZH::MediaWords;

use strict;
use Encode;
use Unicode::UCD 'charinfo';
use Unicode::UCD 'general_categories';
use utf8;

my $EOS = "\001";
my $P   = q/[。？！]/;                            ## PUNCTUATION
my $AP  = q/(？：‘|“|》|\）|\]|』|\})?/;    ## AFTER PUNCTUATION
my $PAP = $P . $AP;

sub get_sentences
{
    my $text = shift;
    $text =~ s/\n\s*\n/$EOS/gso;                     ## double new-line means a different sentence.
    $text =~ s/($PAP)/$1$EOS/gso;
    $text =~ s/(\s$P)/$1$EOS/gso;                    # breake also when single letter comes before punc.
    $text =~ s/\s/$EOS/gso;
    $text =~ s/$EOS+/$EOS/gso;
    my $sentences;
    @$sentences = split( /$EOS/, $text );

    return $sentences;
}

#returns 1 if a character is Chinese, 0 otherwise
sub _is_Chinese
{
    my $char = shift;
    if ( $char =~ m!^(\p{Han})! )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

#to determine if a given character is a Latin letter
sub _is_Latin
{
    my $char = shift;
    if ( $char =~ m!^(\p{Latin})! )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

#get the number of Chinese characters in text
sub number_of_Chinese_characters
{
    my $string = shift;

    my @chars = split( //, $string );

    my @chinese_chars = grep { _is_Chinese( $_ ) } @chars;

    my $number_of_chinese_chars = scalar( @chinese_chars );

    return $number_of_chinese_chars;
}

#get the number of Latin letters in text
sub number_of_Latin_letters
{
    my $string = shift;

    my @chars = split( //, $string );

    my @Latin_letters = grep { _is_Latin( $_ ) } @chars;

    my $number_of_Latin_letters = scalar( @Latin_letters );

    return $number_of_Latin_letters;

}

#to test if a text is Chinese
sub text_is_Chinese
{
    my $text = shift;
    if ( 3 * number_of_Chinese_characters( $text ) > number_of_Latin_letters( $text ) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

1;
