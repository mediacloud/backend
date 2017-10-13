def _make_tag_checker(element_kwargs, attr='content'):
    """Build a function for extracting a date from a BeautifulSoup object.

    Attributes
    ----------
    element : str
        html element name to search for
    element_kwargs : dict[str]->str
        attributes on the desired html element
    attr : str, optional
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
        for ele in soup.find_all(attrs=element_kwargs):
            value = ele.get(attr)
            if value is not None:
                return value
        return None
    return tag_checker


def get_tag_checkers():
    """Get an iterable of functions for extracting dates from html articles."""
    return (
        _make_tag_checker({'property': 'article:published'}),  # nytimes
        _make_tag_checker({'itemprop': 'datePublished'}),  # youtube
        _make_tag_checker({'itemprop': 'datePublished'}, attr='datetime'),  # nymag
        _make_tag_checker({'property': 'article:published_time'}),  # thehill
        _make_tag_checker({'name': 'DC.date.published'}),  # WHO
        _make_tag_checker({'name': 'pubDate'}),  # nielson
        # buzzfeed
        _make_tag_checker({'class': 'buzz-timestamp__time js-timestamp__time'}, attr='data-unix'),
        _make_tag_checker({'class': 'published'}, attr='title'),  # sudantribune
        _make_tag_checker({'class': 'timestamp'}, attr='datetime'),  # propublica
        _make_tag_checker({'property': 'nv:date'}),  # msnbc
        # The following are from (MIT Licensed) https://github.com/codelucas/newspaper
        _make_tag_checker({'property': 'rnews:datePublished'}),
        _make_tag_checker({'name': 'OriginalPublicationDate'}),
        _make_tag_checker({'property': 'og:published_time'}),
        _make_tag_checker({'name': 'article_date_original'}),
        _make_tag_checker({'name': 'publication_date'}),
        _make_tag_checker({'name': 'sailthru.date'}),
        _make_tag_checker({'name': 'PublishDate'}),
        _make_tag_checker({'name': 'pubdate'}, attr='datetime'),
    )
