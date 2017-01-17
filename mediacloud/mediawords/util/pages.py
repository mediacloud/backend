from typing import Union


class McPagesException(Exception):
    pass


class Pages(object):
    """Utility class for calculating pages (copied from Data::Page, used in include/pager.tt2)

    Makes the functionality more portable to Python because it's our own code, not someone else's.

    Copyright belongs to http://search.cpan.org/~lbrocard/Data-Page-2.02/ author."""

    __total_entries = None
    __entries_per_page = None
    __current_page = None

    def __init__(self, total_entries: int, entries_per_page: int, current_page: int):
        if entries_per_page < 1:
            raise McPagesException("Fewer than one entry per page!")

        self.__total_entries = total_entries
        self.__entries_per_page = entries_per_page
        self.__current_page = current_page

    def previous_page(self) -> Union[int, None]:
        """Returns the previous page number if one exists, or None.

        if page.previous_page() is not None:
            print("Previous page number: %d" % page.previous_page())
        """
        if self.__current_page > 1:
            return self.__current_page - 1
        else:
            return None

    def next_page(self) -> Union[int, None]:
        """Returns the next page number if one exists, or None.

        if page.next_page() is not None:
            print("Next page number: %d" % page.next_page())
        """
        if self.__current_page < self.__last_page():
            return self.__current_page + 1
        else:
            return None

    def first(self) -> int:
        """Returns the number of the first entry on the current page.

        print("Showing entries from: %d" % page.first())
        """
        if self.__total_entries == 0:
            return 0
        else:
            return ((self.__current_page - 1) * self.__entries_per_page) + 1

    def last(self) -> int:
        """Returns the number of the last entry on the current page.

        print("Showing entries to: %d" % page.last())
        """
        if self.__current_page == self.__last_page():
            return self.__total_entries
        else:
            return self.__current_page * self.__entries_per_page

    def __last_page(self):
        """Returns the total number of pages of information.

        print("Pages range to: %d" % .page.__last_page())
        """
        pages = self.__total_entries / self.__entries_per_page
        if pages == int(pages):
            last_page = pages
        else:
            last_page = int(pages) + 1

        if last_page < 1:
            last_page = 1

        return last_page
