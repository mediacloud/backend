package MediaWords::Languages::Language;

#
# Generic language plug-in for Media Words, also a singleton to a configured language.
#
# Has to be overloaded by a specific language plugin (think of this as an abstract class).
#
# Also, use this to get an instance of a currently configured language, e.g.:
#   my $lang = MediaWords::Languages::Language::lang();
#   my $stopwords = $lang->get_tiny_stop_words();
#

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Moose::Role;
use Lingua::Stem::Snowball;
use Lingua::StopWords;
use Locale::Country::Multilingual { use_io_layer => 1 };
use MediaWords::Util::Config;

use File::Basename ();
use Cwd            ();

#
# START OF THE SUBCLASS INTERFACE
#

# Returns a string language code (e.g. 'en_US')
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
#       return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/en_US_stoplist_tiny.txt' );
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

# Returns a list of sentences from a story text
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

# Also, you might want to override 'get_locale_country_object' (see below) to implement your own
# way to fetch a list of country codes and countries. Do that only if you have problems with
# country detection.

#
# END OF THE SUBCLASS INTERFACE
#

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

# Instance of Locale::Country::Multilingual (if needed), lazy-initialized in get_locale_country_object()
has 'locale_country_object' => (
    is      => 'rw',
    default => 0,
);

# Cached stopwords
has 'cached_tiny_stop_words' => (
    is      => 'rw',
    default => 0,
);
has 'cached_short_stop_words' => (
    is      => 'rw',
    default => 0,
);
has 'cached_long_stop_words' => (
    is      => 'rw',
    default => 0,
);

# Cached stopword stems
has 'cached_tiny_stop_word_stems' => (
    is      => 'rw',
    default => 0,
);
has 'cached_short_stop_word_stems' => (
    is      => 'rw',
    default => 0,
);
has 'cached_long_stop_word_stems' => (
    is      => 'rw',
    default => 0,
);

# Instance of a configured language (e.g. MediaWords::Languages::en_US), lazy-initialized in lang()
my $_instance = 0;

# Returns a (singleton) instance of a particular configured language
sub lang
{
    if ( $_instance == 0 )
    {

        # Load a module of a configured language
        my $module = 'MediaWords::Languages::' . MediaWords::Util::Config::get_config->{ mediawords }->{ language };
        eval {
            ( my $file = $module ) =~ s|::|/|g;
            require $file . '.pm';
            $module->import();
            1;
        } or do
        {
            my $error = $@;
            die( "Error while loading module: $error" );
        };

        $_instance = $module->new();
    }

    return $_instance;
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

# Returns an object complying with Locale::Codes::API "protocol" (e.g. an instance of
# Locale::Country::Multilingual) for fetching a list of country codes and countries.
# Might be overriden; the default implementation returns an instance of
# Locale::Country::Multilingual initialized with whatever is returned by 'get_language_code'.
sub get_locale_country_object
{
    my $self = shift;

    if ( $self->locale_country_object == 0 )
    {
        $self->locale_country_object( Locale::Country::Multilingual->new() );
        $self->locale_country_object->set_lang( $self->get_language_code() );
    }

    return $self->locale_country_object;
}

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

# Returns stopwords read from a file
sub _get_stop_words_from_file
{
    my ( $self, $filename ) = @_;

    my $relative_path = '../../../';    # Path to base of project relative to the current file
    my $base_dir = Cwd::realpath( File::Basename::dirname( __FILE__ ) . '/' . $relative_path );
    $filename = $base_dir . '/' . $filename;

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
    while ( $sentence =~ m~(\w[\w']*)~g )
    {
        push( @{ $tokens }, lc( $1 ) );
    }

    return $tokens;
}

1;
