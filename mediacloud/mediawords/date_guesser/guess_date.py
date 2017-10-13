import arrow
from bs4 import BeautifulSoup

from .constants import Accuracy, LOCALE
from .dates import MultiDateParser
from .html import get_tag_checkers
from .urls import parse_url_for_date


class DateGuesser(object):
    def __init__(self):
        self.parser = MultiDateParser(arrow.parser.DateTimeParser(locale=LOCALE))
        self.tag_checkers = get_tag_checkers()

    def guess_date(self, url, html):
        """Guess the date of publication of a webpage.

        Attributes
        ----------
        url : str
            url used to retrieve the webpage
        html : str
            raw html of the webpage

        Returns
        -------
        (datetime or None, Accuracy)
            In case a reasonable guess can be made, returns a datetime and Enum of accuracy
        """
        # Try using the url
        date, accuracy = parse_url_for_date(url)

        # Not sure how we could get datetime from a url, but this can be changed to go faster
        if accuracy is Accuracy.DATETIME:
            return date, accuracy

        # Try looking for specific elements
        soup = BeautifulSoup(html, 'lxml')
        for tag_checker in self.tag_checkers:
            date_string = tag_checker(soup)
            new_date, new_accuracy = self.parser.parse(date_string)
            if new_accuracy > accuracy:
                date, accuracy = new_date, new_accuracy

        # TODO: in case of partial match above, look for all date strings, and
        # return any with extra accuracy
        return date, accuracy
