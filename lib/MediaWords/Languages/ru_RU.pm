package MediaWords::Languages::ru_RU;
use Moose;
with 'MediaWords::Languages::Language';

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;


sub get_language_code
{
    return 'ru_RU';
}


sub get_stop_words
{
    my $self = shift;
    # I'm not sure why Lingua::StopWords is not used in this case. A list is too short maybe?
    return $self->_get_stop_words_from_file("$FindBin::Bin/../lib/MediaWords/Languages/ru_RU_stoplist.txt");
}


sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball('ru', 'UTF-8', \@_);
}


sub tokenize
{
    my ($self, $sentence) = @_;
    return $self->_tokenize_with_spaces($sentence);
}


1;
