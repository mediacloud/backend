package MediaWords::Languages::Language;

# Generic language plug-in for Media Words.
# Has to be overloaded by a specific language plugin (think of this as an abstract class).

use strict;
use warnings;

BEGIN
{
    use FindBin;
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Moose::Role;
use Lingua::Stem::Snowball;
use Lingua::StopWords;


# Returns a string language code (e.g. 'en_US')
requires 'get_language_code';

# Returns a hashref with list of stop words (a "stoplist") for the language
# where the keys are all stopwords and the values are all 1.
requires 'get_stop_words';

# Returns a reference to an array of stemmed words (using Lingua::Stem::Snowball or some other way)
requires 'stem';

# Returns a tokenized sentence for the language
requires 'tokenize';


# Lingua::Stem::Snowball instance (if needed), lazy-initialized in _stem_with_lingua_stem_snowball()
has 'stemmer' => (
    is      => 'rw',
    default => 0,
);

# Lingua::Stem::Snowball language and encoding
has 'stemmer_language' => (
    is      => 'rw',
    default => 0,
);
has 'stemmer_encoding' => (
    is      => 'rw',
    default => 0,
);


# Lingua::Stem::Snowball helper
sub _stem_with_lingua_stem_snowball
{
    my ($self, $language, $encoding, $ref_words) = @_;

    # (Re-)initialize stemmer if needed
    if ($self->stemmer == 0 or $self->stemmer_language ne $language or $self->stemmer_encoding ne $encoding) {
        $self->stemmer(Lingua::Stem::Snowball->new(
            lang     => $language,
            encoding => $encoding
        ));
    }

    my @stems = $self->stemmer->stem( $ref_words );
    return \@stems;
}


# Lingua::StopWords helper
sub _get_stop_words_with_lingua_stopwords
{
    my ($self, $language, $encoding) = @_;

    return Lingua::StopWords::getStopWords($language, $encoding);
}


# Returns stopwords read from a file
sub _get_stop_words_from_file
{
    my ($self, $filename) = @_;

    my %stopwords;
    
    # Read stoplist, ignore comments, ignore empty lines
    open STOPLIST, $filename or die $!;
    while (my $line = <STOPLIST>) {
        chomp($line);
        if ($line and $line !~ /\s*#/) {
            $stopwords{$line} = 1;
        }
    }
    close(STOPLIST);

    return \%stopwords;
}


# Converts an array into hashref (for a list of stop words)
sub _array_to_hashref
{
    my $self = shift;
    my %hash = map { $_ => 1 } @_;
    return \%hash;
}


# Tokenizes a sentence with spaces (for Latin languages)
sub _tokenize_with_spaces
{
    my ( $self, $sentence ) = @_;
    $sentence = [ $sentence ];

    my $tokens = [];
    while ( $sentence->[ 0 ] =~ m~(\w[\w']*)~g )
    {
        push( @{ $tokens }, lc( $1 ) );
    }

    return $tokens;
}

1;
