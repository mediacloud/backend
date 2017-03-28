import MeCab
from nltk import RegexpTokenizer, PunktSentenceTokenizer
import os

from mediawords.util.log import create_logger
from mediawords.util.paths import mc_root_path
from mediawords.util.perl import decode_object_from_bytes_if_needed

l = create_logger(__name__)


class McJapaneseTokenizerException(Exception):
    """McJapaneseTokenizer class exception."""
    pass


class McJapaneseTokenizer(object):
    """Japanese language tagger that uses MeCab."""

    # MeCab instance
    __mecab = None

    __japanese_sentence_tokenizer = RegexpTokenizer(
        r'([^！？。]*[！？。])',
        gaps=True,  # don't discard non-Japanese text
        discard_empty=True,
    )

    __non_japanese_sentence_tokenizer = PunktSentenceTokenizer()

    # MeCab-returned string that denotes that term is punctuation
    __MECAB_POS_PUNCTUATION = "記号"

    def __init__(self):
        """Initialize MeCab tokenizer."""

        dictionary_path = os.path.join(mc_root_path(), "lib/MediaWords/Languages/resources/ja/mecab-ipadic-neologd/")

        if not os.path.isdir(dictionary_path):
            raise McJapaneseTokenizerException("""
                MeCab dictionary directory was not found: %s
                Maybe you forgot to initialize Git submodules?
                """ % dictionary_path)

        if not os.path.isfile(os.path.join(dictionary_path, "sys.dic")):
            raise McJapaneseTokenizerException("""
                MeCab dictionary directory does not contain a dictionary: %s
                Maybe you forgot to run ./install/install_mecab-ipadic-neologd.sh?
                """ % dictionary_path)

        try:
            self.__mecab = MeCab.Tagger("--dicdir=%s" % dictionary_path)
        except Exception as ex:
            raise McJapaneseTokenizerException("Unable to initialize MeCab: %s" % str(ex))

    def tokenize_text_to_sentences(self, text: str) -> list:
        """Tokenize Japanese text into sentences."""

        text = decode_object_from_bytes_if_needed(text)

        if text is None:
            l.warning("Text to tokenize into sentences is None.")
            return []

        text = text.strip()

        if len(text) == 0:
            return []

        # First split Japanese text
        japanese_sentences = self.__japanese_sentence_tokenizer.tokenize(text)
        sentences = []
        for sentence in japanese_sentences:
            # ...then naively split non-Japanese text
            non_japanese_sentences = self.__non_japanese_sentence_tokenizer.tokenize(sentence)

            sentences += non_japanese_sentences

        # Trim whitespace
        sentences = [sentence.strip() for sentence in sentences]

        return sentences

    def tokenize_sentence_to_words(self, sentence: str) -> list:
        """Tokenize Japanese sentence into words.
        
        Removes punctuation, leaves stopwords in-place."""

        sentence = decode_object_from_bytes_if_needed(sentence)

        if sentence is None:
            l.warning("Sentence to tokenize into words is None.")
            return []

        sentence = sentence.strip()

        if len(sentence) == 0:
            return []

        parsed_text = self.__mecab.parse(sentence).strip()
        parsed_tokens = parsed_text.split("\n")

        words = []
        for parsed_token_line in parsed_tokens:
            if "\t" in parsed_token_line:

                # "表層形\t品詞,品詞細分類1,品詞細分類2,品詞細分類3,活用型,活用形,原形,読み,発音"
                # (https://taku910.github.io/mecab/)
                primary_form_and_analysis_result = parsed_token_line.split("\t")
                if len(primary_form_and_analysis_result) != 2:
                    l.warning("Line '%s' does not contain expected number of tabs." % parsed_token_line)
                    continue

                primary_form = primary_form_and_analysis_result[0]
                analysis_result = primary_form_and_analysis_result[1]

                part_of_speech = analysis_result.split(",")[0]

                if part_of_speech != self.__MECAB_POS_PUNCTUATION:
                    words.append(primary_form)

            else:
                # Ignore all the "EOS" stuff
                pass

        return words
