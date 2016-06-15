Media Cloud language support
============================

MediaCloud language support builds upon the Lingua:: Perl packages, in particular, Lingua::StopWords for defining a
list of words that should not be included in most textual analyses, and
[Lingua::Stem](http://search.cpan.org/dist/Lingua-Stem/lib/Lingua/Stem.pod) for allowing words with similar meanings to
be grouped together based on a common word stem.

Media Cloud does not need any special language support to collect data for a given language.  For example, we have no
language support for Chinese, but the system is still capable of crawling and collecting Chinese language content.

The language support described in this file is mostly used for two purposes.  Most importantly, the sentence parsing
is used to break each story into the sentences which are stores in the story_sentences table.  That table is used
as the source of content for the source exports to solr and is also used in various places in the code as a
representation of the text of each story.

Secondarily, the tokenizing, stemming, and stopwording are used for the word counting, which provides the data for
the various word counting api end points (including wc/list, topics/<id>/wc/list, and stories_public/get_word_matrix).
Contents in a language not supported by Media Cloud will still be processed by those end points, but the results will
not be stemmed or stopworded.

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
	* If sentences in your language are separated by a period (.), you can just use the integrated
      `$self->_tokenize_with_spaces( $sentence )` helper.
		* However, you still need to create / acquire a so-called non-breaking prefix file. See http://search.cpan.org/~achimru/Lingua-Sentence-1.00/lib/Lingua/Sentence.pm#Nonbreaking_Prefixes_Files for
        more information.

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
