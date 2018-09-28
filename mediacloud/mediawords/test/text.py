import colorama
import difflib
import re

from mediawords.util.perl import decode_object_from_bytes_if_needed

colorama.init()


class TestCaseTextUtilities(object):

    @staticmethod
    def __normalize_text(text: str) -> str:
        """Normalize text by stripping whitespace and such."""
        text = text.replace("\r\n", "\n")
        text = re.sub(r'\s+', ' ', text)
        text = text.strip()
        return text

    @staticmethod
    def __colorize_difflib_ndiff_line_output(diff_line: str) -> str:
        """Colorize a single line of difflib.ndiff() output by adding some ANSI colors."""
        if diff_line.startswith('+'):
            diff_line = colorama.Fore.GREEN + diff_line + colorama.Fore.RESET
        elif diff_line.startswith('-'):
            diff_line = colorama.Fore.RED + diff_line + colorama.Fore.RESET
        elif diff_line.startswith('^'):
            diff_line = colorama.Fore.BLUE + diff_line + colorama.Fore.RESET

        return diff_line

    # noinspection PyPep8Naming
    def assertTextEqual(self, got_text: str, expected_text: str, msg: str = None) -> None:
        """An equality assertion for two texts.

        For the purposes of this function, a valid ordered sequence type is one
        which can be indexed, has a length, and has an equality operator.

        Args:
            got_text: First text to be compared (e.g. received from a tested function).
            expected_text: Second text (e.g. the one that is expected from a tested function).
            msg: Optional message to use on failure instead of a list of differences.
        """

        got_text = decode_object_from_bytes_if_needed(got_text)
        expected_text = decode_object_from_bytes_if_needed(expected_text)
        msg = decode_object_from_bytes_if_needed(msg)

        if got_text is None:
            raise TypeError("Got text is None.")
        if expected_text is None:
            raise TypeError("Expected text is None.")

        got_text = self.__normalize_text(got_text)
        expected_text = self.__normalize_text(expected_text)

        if got_text == expected_text:
            return

        got_words = got_text.split()
        expected_words = expected_text.split()

        if got_words == expected_words:
            return

        if msg is None:

            differences = []

            for diff_line in difflib.ndiff(expected_words, got_words):
                diff_line = self.__colorize_difflib_ndiff_line_output(diff_line=diff_line)
                differences.append(diff_line)

            msg = " ".join(differences)

        raise AssertionError(msg)
