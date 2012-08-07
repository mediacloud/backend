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


# Chinese segmenter, lazy-initialized in tokenize()
has 'segmenter' => (
    is      => 'rw',
    default => 0,
);


sub get_language_code
{
    return 'zh_CN';
}


sub get_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file("$FindBin::Bin/../lib/MediaWords/Languages/zh_CN_stoplist.txt");
}


sub stem
{
    my $self = shift;
    # Don't stem anything.
    return \@_;
}


sub tokenize
{
    my ($self, $sentence) = @_;

    # Initialize segmenter (if needed)
    if ($self->segmenter == 0) {
        my %par = ();
        $par{ 'dic_encoding' } = 'utf8';
        $par{ 'dic' }          = "$FindBin::Bin/../lib/Lingua/ZH/dict.txt";
        $self->segmenter(Lingua::ZH::WordSegmenter->new( %par ));
    }
    
    # Tokenize
    my $i;
    my $segmenter = $self->segmenter;
    $sentence = encode( 'utf8', $sentence );
    my $segs = $segmenter->seg( $sentence, 'utf8' );
    my $tokens;
    @$tokens = split( / /, $segs );
    my $token;

    foreach $token ( @$tokens ) {
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
