package MediaWords::Languages::Language;

#
# Generic language plug-in for Media Words, also a factory of configured + enabled languages.
#
# Has to be overloaded by a specific language plugin (think of this as an abstract class).
#
# See doc/README.languages for instructions.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use utf8;

use Moose::Role;
use Lingua::Stem::Snowball;
use Lingua::StopWords;
use Lingua::Sentence;
use Scalar::Defer;

use File::Basename ();
use Cwd            ();

#
# LIST OF ENABLED LANGUAGES
#
my @_enabled_languages = (
    'da',    # Danish
    'de',    # German
    'en',    # English
    'es',    # Spanish
    'fi',    # Finnish
    'fr',    # French
    'hu',    # Hungarian
    'it',    # Italian
    'lt',    # Lithuanian
    'nl',    # Dutch
    'no',    # Norwegian
    'pt',    # Portuguese
    'ro',    # Romanian
    'ru',    # Russian
    'sv',    # Swedish
    'tr',    # Turkish

    # Chinese disabled because of poor word segmentation
    #'zh',                                  # Chinese
);

#
# START OF THE SUBCLASS INTERFACE
#

# Returns a string ISO 639-1 language code (e.g. 'en')
requires 'get_language_code';

# Returns a hashref to a "tiny" (~200 entries) list of stop words for the language
# where the keys are all stopwords and the values are all 1.
#
# If Lingua::StopWords module supports the language you're about to add, you can use the module helper:
#
#   sub fetch_and_return_tiny_stop_words
#   {
#       my $self = shift;
#       return $self->_get_stop_words_with_lingua_stopwords( 'en', 'UTF-8' );
#   }
#
# If you've decided to store a stoplist in an external file, you can use the module helper:
#
#   sub fetch_and_return_tiny_stop_words
#   {
#       my $self = shift;
#       return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/en_stoplist_tiny.txt' );
#   }
#
requires 'fetch_and_return_tiny_stop_words';

# Returns a hashref to a "short" (~1000 entries) list of stop words for the language
# where the keys are all stopwords and the values are all 1.
# Also see a description of the available helpers above.
requires 'fetch_and_return_short_stop_words';

# Returns a hashref to a "long" (~4000+ entries) list of stop words for the language
# where the keys are all stopwords and the values are all 1.
# Also see a description of the available helpers above.
requires 'fetch_and_return_long_stop_words';

# Returns a reference to an array of stemmed words (using Lingua::Stem::Snowball or some other way)
# A parameter is an array.
#
# If Lingua::Stem::Snowball module supports the language you're about to add, you can use the module helper:
#
#   sub stem
#   {
#       my $self = shift;
#       return $self->_stem_with_lingua_stem_snowball( 'fr', 'UTF-8', \@_ );
#   }
#
requires 'stem';

# Returns a word length limit of a language (0 -- no limit)
requires 'get_word_length_limit';

# Returns a list of sentences from a story text (tokenizes text into sentences)
requires 'get_sentences';

# Returns a reference to an array with a tokenized sentence for the language
#
# If the words in a sentence are separated by spaces (as with most of the languages with
# a Latin-derived alphabet), you can use the module helper:
#
#   sub tokenize
#   {
#       my ( $self, $sentence ) = @_;
#       return $self->_tokenize_with_spaces( $sentence );
#   }
#
requires 'tokenize';

#
# END OF THE SUBCLASS INTERFACE
#

# Lingua::Stem::Snowball instance (if needed), lazy-initialized in _stem_with_lingua_stem_snowball()
has 'stemmer' => ( is => 'rw', default => 0 );

# Lingua::Stem::Snowball language and encoding
has 'stemmer_language' => ( is => 'rw', default => 0 );
has 'stemmer_encoding' => ( is => 'rw', default => 0 );

# Lingua::Sentence instance (if needed), lazy-initialized in _tokenize_text_with_lingua_sentence()
has 'sentence_tokenizer' => ( is => 'rw', default => 0 );

# Lingua::Sentence language
has 'sentence_tokenizer_language' => ( is => 'rw', default => 0 );

# Cached stopwords
has 'cached_tiny_stop_words'  => ( is => 'rw', default => 0 );
has 'cached_short_stop_words' => ( is => 'rw', default => 0 );
has 'cached_long_stop_words'  => ( is => 'rw', default => 0 );

# Cached stopword stems
has 'cached_tiny_stop_word_stems'  => ( is => 'rw', default => 0 );
has 'cached_short_stop_word_stems' => ( is => 'rw', default => 0 );
has 'cached_long_stop_word_stems'  => ( is => 'rw', default => 0 );

# Cached noise strings regular expression
has 'cached_noise_strings_regex' => ( is => 'rw', default => 0 );

# Instances of each of the enabled languages (e.g. MediaWords::Languages::en, MediaWords::Languages::lt, ...)
my $_lang_instances = lazy
{
    # lazy load this here because this is very slow to load
    require MediaWords::Util::IdentifyLanguage;    # to check if the language can be identified

    my $lang_instances;

    # Load enabled language modules
    foreach my $language_to_load ( @_enabled_languages )
    {

        # Check if the language is supported by the language identifier
        unless ( MediaWords::Util::IdentifyLanguage::language_is_supported( $language_to_load ) )
        {
            die(
"Language module '$language_to_load' is enabled but the language is not supported by the language identifier."
            );
        }

        # Load module
        my $module = 'MediaWords::Languages::' . $language_to_load;
        eval {
            ( my $file = $module ) =~ s|::|/|g;
            require $file . '.pm';
            $module->import();
            1;
        } or do
        {
            my $error = $@;
            die( "Error while loading module for language '$language_to_load': $error" );
        };

        # Initialize an instance of the particular language module
        $lang_instances->{ $language_to_load } = $module->new();
    }

    return $lang_instances;
};

# (static) Returns 1 if language is enabled, 0 if not
sub language_is_enabled($)
{
    my $language_code = shift;

    if ( exists $_lang_instances->{ $language_code } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# (static) Returns language module instance for the language code, 0 on error
sub language_for_code($)
{
    my $language_code = shift;

    unless ( language_is_enabled( $language_code ) )
    {
        return 0;
    }

    return $_lang_instances->{ $language_code };
}

# (static) Returns default language module instance (English)
sub default_language
{
    my $language = language_for_code( default_language_code() );
    unless ( $language )
    {
        die "Default language 'en' is not enabled.";
    }

    return $language;
}

# (static) Returns default language code ('en' for English)
sub default_language_code
{
    return 'en';
}

# (static) Get an array of enabled languages
sub enabled_languages
{
    return @_enabled_languages;
}

# Cached stop words
sub get_tiny_stop_words
{
    my $self = shift;

    if ( $self->cached_tiny_stop_words == 0 )
    {
        $self->cached_tiny_stop_words( $self->fetch_and_return_tiny_stop_words() );
    }

    return $self->cached_tiny_stop_words;
}

sub get_short_stop_words
{
    my $self = shift;

    if ( $self->cached_short_stop_words == 0 )
    {
        $self->cached_short_stop_words( $self->fetch_and_return_short_stop_words() );
    }

    return $self->cached_short_stop_words;
}

sub get_long_stop_words
{
    my $self = shift;

    if ( $self->cached_long_stop_words == 0 )
    {
        $self->cached_long_stop_words( $self->fetch_and_return_long_stop_words() );
    }

    return $self->cached_long_stop_words;
}

# Get stop word stems
sub get_tiny_stop_word_stems
{
    my $self = shift;

    if ( $self->cached_tiny_stop_word_stems == 0 )
    {
        my $stems = [ keys( %{ $self->get_tiny_stop_words() } ) ];
        my $hash;

        $stems = $self->stem( @{ $stems } );

        for my $stem ( @{ $stems } )
        {
            $hash->{ $stem } = 1;
        }

        $self->cached_tiny_stop_word_stems( $hash );
    }

    return $self->cached_tiny_stop_word_stems;
}

sub get_short_stop_word_stems
{
    my $self = shift;

    if ( $self->cached_short_stop_word_stems == 0 )
    {
        my $stems = [ keys( %{ $self->get_short_stop_words() } ) ];
        my $hash;

        $stems = $self->stem( @{ $stems } );

        for my $stem ( @{ $stems } )
        {
            $hash->{ $stem } = 1;
        }

        $self->cached_short_stop_word_stems( $hash );
    }

    return $self->cached_short_stop_word_stems;
}

sub get_long_stop_word_stems
{
    my $self = shift;

    if ( $self->cached_long_stop_word_stems == 0 )
    {
        my $stems = [ keys( %{ $self->get_long_stop_words() } ) ];
        my $hash;

        $stems = $self->stem( @{ $stems } );

        for my $stem ( @{ $stems } )
        {
            $hash->{ $stem } = 1;
        }

        $self->cached_long_stop_word_stems( $hash );
    }

    return $self->cached_long_stop_word_stems;
}

# return stop word stems of $length 'tiny', 'short', or 'long'.  die if the $length is unsupported
sub get_stop_word_stems($)
{
    my ( $self, $length ) = @_;

    return $self->get_tiny_stop_word_stems  if ( $length eq 'tiny' );
    return $self->get_short_stop_word_stems if ( $length eq 'short' );
    return $self->get_long_stop_word_stems  if ( $length eq 'long' );

    die( "Unknown stop word length '$length'" );
}

around 'stem' => sub {
    my $orig = shift;
    my $self = shift;

    my @words = @_;

    # Normalize apostrophe so that "it’s" and "it's" get treated identically
    # (it's being done in _tokenize_with_spaces() too but let's not assume that
    # all tokens that are to be stemmed go through sentence tokenization first)
    s/’/'/g for @words;

    return $self->$orig( @words );
};

# Lingua::Stem::Snowball helper
sub _stem_with_lingua_stem_snowball
{
    my ( $self, $language, $encoding, $ref_words ) = @_;

    # (Re-)initialize stemmer if needed
    if ( $self->stemmer == 0 or $self->stemmer_language ne $language or $self->stemmer_encoding ne $encoding )
    {
        $self->stemmer(
            Lingua::Stem::Snowball->new(
                lang     => $language,
                encoding => $encoding
            )
        );
    }

    my @stems = $self->stemmer->stem( $ref_words );

    return \@stems;
}

# Lingua::StopWords helper
sub _get_stop_words_with_lingua_stopwords
{
    my ( $self, $language, $encoding ) = @_;
    return Lingua::StopWords::getStopWords( $language, $encoding );
}

# Lingua::Sentence helper
sub _tokenize_text_with_lingua_sentence
{
    my ( $self, $language, $nonbreaking_prefixes_file, $text ) = @_;

    # (Re-)initialize stemmer if needed
    if ( $self->sentence_tokenizer == 0 or $self->sentence_tokenizer ne $language )
    {
        $self->sentence_tokenizer( Lingua::Sentence->new( $language, $nonbreaking_prefixes_file ) );
    }

    unless ( defined $text )
    {
        warn "Text is undefined.";
        return undef;
    }

    # Only "\n\n" (not a single "\n") denotes the end of sentence, so remove single line breaks
    $text =~ s/([^\n])\n([^\n])/$1 $2/gs;

    # Remove asterisks from lists
    $text =~ s/  */ /gs;

    $text =~ s/\n\s*\n/\n\n/gso;
    $text =~ s/\n\n\n*/\n\n/gso;
    $text =~ s/\n\n/\n/gso;

    # Replace tabs with spaces
    $text =~ s/\t/ /gs;

    # Replace non-breaking spaces with normal spaces
    $text =~ s/\x{a0}/ /gs;

    # Replace multiple spaces with a single space
    $text =~ s/  +/ /gs;

    # The above regexp and html stripping often leave a space before the period at the end of a sentence
    $text =~ s/ +\./\./g;

    # We see lots of cases of missing spaces after sentence ending periods
    # (has a hardcoded lower limit of characters because otherwise it breaks Portuguese "a.C.." abbreviations and such)
    $text =~ s/([[:lower:]]{2,})\.([[:upper:]][[:lower:]]{1,})/$1. $2/g;

    # Trim whitespace from start / end of the whole string
    $text =~ s/^\s*//g;
    $text =~ s/\s*$//g;

    # Replace Unicode's "…" with "..."
    $text =~ s/…/.../g;

    # FIXME: fix "bla bla... yada yada"? is it two sentences?
    # FIXME: fix "text . . some more text."?

    unless ( $text )
    {
        say STDERR "Text is empty after processing it.";
        return [];
    }

    # Split to sentences
    my @sentences = $self->sentence_tokenizer->split_array( $text );

    # Trim whitespace from start / end of each of the sentences
    @sentences = grep( s/^\s*//g, @sentences );
    @sentences = grep( s/\s*$//g, @sentences );

    # Remove empty sentences (buggy Lingua::Sentence I guess)
    @sentences = grep( /\S/, @sentences );

    return \@sentences;
}

# Returns the root directory
sub _base_dir
{
    my $relative_path = '../../../';    # Path to base of project relative to the current file
    my $base_dir = Cwd::realpath( File::Basename::dirname( __FILE__ ) . '/' . $relative_path );
    return $base_dir;
}

# Returns stopwords read from a file
sub _get_stop_words_from_file
{
    my ( $self, $filename ) = @_;

    $filename = _base_dir() . '/' . $filename;

    my %stopwords;

    # Read stoplist, ignore comments, ignore empty lines
    use open IN => ':utf8';
    open STOPLIST, $filename or die "Unable to read '$filename': $!";
    while ( my $line = <STOPLIST> )
    {

        # Remove comments
        $line =~ s/\s*?#.*?$//s;

        chomp( $line );

        if ( length( $line ) )
        {
            $stopwords{ $line } = 1;
        }
    }
    close( STOPLIST );

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

    my $tokens = [];
    while ( $sentence =~ m~(\w[\w'’\-]*)~g )
    {
        my $token = $1;

        # Normalize apostrophe so that "it’s" and "it's" get treated identically
        $token =~ s/’/'/g;

        push( @{ $tokens }, lc( $token ) );
    }

    return $tokens;
}

1;
