def _make_tag_checker(element, element_kwargs, attr):
    """Build a function for extracting a date from a BeautifulSoup object.

    Attributes
    ----------
    element : str
        html element name to search for
    element_kwargs : dict[str]->str
        attributes on the desired html element
    attr : str
        attribute on the element with date information

    Returns
    -------
    function(BeautifulSoup) -> str or None
    """
    def tag_checker(soup):
        """Extract a date string from a BeautifulSoup object.

        Attributes
        ----------
        soup : BeautifulSoup
            Parsed html to search through

        Returns
        -------
        str or None
            The desired date string if found, or None otherwise
        """
        ele = soup.find(name=element, attrs=element_kwargs)
        if ele is not None:
            return ele.get(attr)
        return None
    return tag_checker


def get_tag_checkers():
    """Get an iterable of functions for extracting dates from html articles."""
    return (
        _make_tag_checker('meta', {'property': 'article:published'}, 'content'),  # nytimes
        _make_tag_checker('meta', {'itemprop': 'datePublished'}, 'content'),  # youtube
        _make_tag_checker('time', {'itemprop': 'datePublished'}, 'datetime'),  # nymag
        _make_tag_checker('meta', {'property': 'article:published_time'}, 'content'),  # thehill
        _make_tag_checker('meta', {'name': 'DC.date.published'}, 'content'),  # WHO
        _make_tag_checker('meta', {'name': 'pubDate'}, 'content'),  # nielson
        _make_tag_checker(
            'time', {'class': 'buzz-timestamp__time js-timestamp__time'}, 'data-unix'),  # buzzfeed
        _make_tag_checker('abbr', {'class': 'published'}, 'title'),  # sudantribune
        _make_tag_checker('time', {'class': 'timestamp'}, 'datetime'),  # propublica
        _make_tag_checker('meta', {'property': 'nv:date'}, 'content')  # msnbc
    )
