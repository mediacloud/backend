package Lingua::ZH::MediaWords;

use Encode;
use Unicode::UCD 'charinfo';
use Unicode::UCD 'general_categories';
use utf8;

$EOS = "\001";
$P   = q/[。？！]/;                            ## PUNCTUATION
$AP  = q/(？：‘|“|》|\）|\]|』|\})?/;    ## AFTER PUNCTUATION
$PAP = $P . $AP;

sub get_sentences
{
    $text = shift;
    $text =~ s/\n\s*\n/$EOS/gso;                  ## double new-line means a different sentence.
    $text =~ s/($PAP)/$1$EOS/gso;
    $text =~ s/(\s$P)/$1$EOS/gso;                 # breake also when single letter comes before punc.
    $text =~ s/\s/$EOS/gso;
    $text =~ s/$EOS+/$EOS/gso;
    my @sentences = split( /$EOS/, $text );

    return @sentences;
}

#this function is used in the subs _is_Chinese and _is_punctuation
sub _codepoint_hex
{
    sprintf "%04x", ord Encode::decode( "UTF-8", shift );
}

#returns 1 if a character is Chinese, 0 otherwise
sub _is_Chinese
{
    my $char     = shift;
    my $charinfo = charinfo( "0x" . _codepoint_hex( $char ) );
    if ( "CJK" eq substr $$charinfo{ name }, 0, 3 )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

#returns 1 if a character is a punctuation, number of space, 0 otherwise
sub _is_punctuation
{
    my $char       = shift;
    my $charinfo   = charinfo( "0x" . _codepoint_hex( $char ) );
    my $categories = general_categories();
    my $category   = $$categories{ $$charinfo{ 'category' } };
    if (   $category eq "OtherPunctuation"
        or $category eq "ClosePunctuation"
        or $category eq "OpenPunctuation"
        or $category eq "DecimalNumber"
        or $category eq "SpaceSeparator" )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

#to test if a text is Chinese
sub text_is_Chinese
{
    my $text = shift;

    my $length = length( $text );
    my $i;
    my $char;
    my $Chinese_characters = 0;
    my $punctuations       = 0;

    #number of tests is larger than length
    my $number_of_tests = 20;
    if ( $length < $number_of_tests )
    {
        $number_of_tests = $length;
    }

    #test the first number of characters
    for ( $i = 0 ; $i < $number_of_tests / 2 ; $i++ )
    {
        $char = encode( "utf8", substr $text, $i, 1 );
        if ( _is_Chinese( $char ) == 1 )
        {
            $Chinese_characters++;
        }
        if ( _is_punctuation( $char ) == 1 )
        {
            $punctuations++;
        }
    }

    #test the last number of characters
    for ( $i = 0 ; $i < $number_of_tests / 2 ; $i++ )
    {
        $char = encode( "utf8", substr $text, $length - 1 - $i, 1 );
        if ( _is_Chinese( $char ) == 1 )
        {
            $Chinese_characters++;
        }
        if ( _is_punctuation( $char ) == 1 )
        {
            $punctuations++;
        }
    }

    #judge if a sentence is Chinese
    if ( $Chinese_characters + $punctuations > ( $number_of_tests - $punctuations ) / 2 )
    {
        return 1;
    }
    else
    {
        return 0;
    }

}

1;
