package MediaWords::Languages::zh_CN;
use Moose;
with 'MediaWords::Languages::Language';

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Encode;
use Encode::HanConvert;
use Lingua::ZH::WordSegmenter;
use Lingua::ZH::MediaWords;

# Chinese segmenter, lazy-initialized in tokenize()
has 'segmenter' => (
    is      => 'rw',
    default => 0,
);

sub get_language_code
{
    return 'zh_CN';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/zh_CN_stoplist_tiny.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->get_tiny_stop_words();
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->get_tiny_stop_words();
}

sub stem
{
    my $self = shift;

    # Don't stem anything.
    return \@_;
}

sub get_word_length_limit
{
    my $self = shift;
    return 0;    # No limit
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;

    # convert traditional characters into simplified characters
    $story_text = Encode::HanConvert::trad_to_simp( $story_text );

    return Lingua::ZH::MediaWords::get_sentences( $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;

    # Initialize segmenter (if needed)
    if ( $self->segmenter == 0 )
    {
        my %par = ();
        $par{ 'dic_encoding' } = 'utf8';
        $par{ 'dic' }          = "$FindBin::Bin/../lib/Lingua/ZH/dict.txt";
        $self->segmenter( Lingua::ZH::WordSegmenter->new( %par ) );
    }

    # Tokenize
    my $i;
    my $segmenter = $self->segmenter;
    $sentence = encode( 'utf8', $sentence );
    my $segs = $segmenter->seg( $sentence, 'utf8' );
    my $tokens;
    @$tokens = split( / /, $segs );
    my $token;

    foreach $token ( @$tokens )
    {
        $token =~ s/[\W\d_\s]+//g;
    }

    for ( $i = 0 ; $i < $#$tokens ; $i++ )
    {
        if ( $tokens->[ $i ] eq "" )
        {
            splice @$tokens, $i, 1;
            $i--;
        }
    }

    return $tokens;
}

1;
