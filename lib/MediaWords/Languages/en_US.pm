package MediaWords::Languages::en_US;
use Moose;
with 'MediaWords::Languages::Language';

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;


sub get_language_code
{
    return 'en_US';
}


sub get_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords('en', 'UTF-8');
}


sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball('en', 'UTF-8', \@_);
}


sub tokenize
{
    my ($self, $sentence) = @_;
    return $self->_tokenize_with_spaces($sentence);
}


1;
