Media Cloud language support
============================

MediaCloud language support builds upon the Lingua:: Perl packages, in particular , Lingua::StopWords for defining a list of words that should not be included in most textual analyses, and [Lingua::Stem](http://search.cpan.org/dist/Lingua-Stem/lib/Lingua/Stem.pod) for allowing words with similar meanings to be grouped together based on a common word stem.

Requirements for adding a new language
--------------------------------------

1. A list of stop words (a stoplist).

    * `Lingua::StopWords` might already support your language. If it does, you're good to go.
    * If not, get a list of stop words for your language and later configure your language's submodule accordingly.
    * After running Media Cloud for some time, you might want to generate a new stoplist straight from the data that you've collected. See `./script/mediawords_generate_stopwords.pl` for an example of how to do that.

2. A stemmer.

    * `Lingua::Stem::Snowball` might already support your language. If it does, you're good to go.
    * If not, find a way to stem words of your language and later configure your language's submodule accordingly.

3. A sentence tokenizer (a list of abbreviations which *do not* end a sentence).

	* You need to find a way to split text into separate sentences.
	* If sentences in your language are separated by a period (.), you can just use the integrated `$self->_tokenize_with_spaces( $sentence )` helper.
		* However, you still need to create / acquire a so-called non-breaking prefix file. See http://search.cpan.org/~achimru/Lingua-Sentence-1.00/lib/Lingua/Sentence.pm#Nonbreaking_Prefixes_Files for more information.

4. (sometimes) A word tokenizer.

    * For some languages, you might need an algorithm that would be able to split sentences into separate words (e.g. Chinese).

Adding support for a new language
---------------------------------

1. Create a subclass of MediaWords::Languages::Language and place it in `lib/MediaWords/Languages/`

    * For example, to add support for French language, create `lib/MediaWords/Languages/fr.pm`.
    * You might want to copy a subclass file of a similar language and modify it to suit your language's requirements.
    	* For example, you can copy `lib/MediaWords/Languages/en.pm` to `lib/MediaWords/Languages/fr.pm`, and then edit `fr.pm` afterwards.

2. Subclass the required Perl subroutines to do the language-specific actions for the language you're about to add.

    * See the top of the `lib/MediaWords/Languages/Language.pm` file for a list of subroutines you have to override.

3. Add the language that you've just added to the `@enabled_languages` array in `lib/MediaWords/Languages/Language.pm`:

	#
	# LIST OF ENABLED LANGUAGES
	#
	my Readonly @_enabled_languages = (
		...
		'xx',	# Your language here
	);
