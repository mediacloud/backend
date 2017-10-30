from .constants import NO_METHOD


def _make_tag_checker(element_kwargs, name=None, attr='content', text=False):
    """Build a function for extracting a date from a BeautifulSoup object.

    Attributes
    ----------
    element : str
        html element name to search for
    element_kwargs : dict[str]->str
        attributes on the desired html element
    name : str, optional
        name of tag to search for
    attr : str, optional
        attribute on the element with date information
    text : bool, optional
        if true, returns the text inside the element, overriding `attr`

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
        for ele in soup.find_all(name, attrs=element_kwargs):
            if text:
                if ele.isSelfClosing:
                    continue
                else:
                    value = ele.get_text()
            else:
                value = ele.get(attr)
            if value is not None:
                ele_str = str(ele)[:200]  # just in case
                method = 'Extracted from tag:\n{}'.format(ele_str)
                return value, method
        return None, NO_METHOD
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
        _make_tag_checker({'class': 'published'}, name='abbr', attr='title'),  # sudantribune
        _make_tag_checker({'class': 'timestamp'}, attr='datetime'),  # propublica
        _make_tag_checker({'property': 'nv:date'}),  # msnbc
        _make_tag_checker({'itemprop': 'dateModified'}),  # techlicious
        _make_tag_checker({'property': 'og:updated_time'}),  # sixthtone
        _make_tag_checker({'class': 'post-meta'}, text=True),  # wordpress
        _make_tag_checker({'name': 'date_published'}),  # usnews
        _make_tag_checker({'class': 'published'}, name='span', text=True),  # innovationfiles.org
        _make_tag_checker({'name': 'citation_date'}),  # ejlt.org
        _make_tag_checker({'name': 'parsely-pub-date'}),  # wired
        _make_tag_checker({'class': 'date-display-single'}),  # cyber.harvard.edu
        _make_tag_checker({'name': 'citation_publication_date'}),  # elsevier
        _make_tag_checker({}, name='time', attr='datetime'), # nature
        _make_tag_checker({'name': 'pubdate'}), # old pbs
        _make_tag_checker({'id': 'absdate'}, attr='value'), # pubmed
        _make_tag_checker({'name': 'Last-Modified'}),  # times of india
        _make_tag_checker({'class': 'byline'}, text=True),  # economic times
        _make_tag_checker({'class': 'metadata'}, name='div', text=True),  # twitter
        _make_tag_checker({'class': 'tweet-timestamp'}, attr='title'),  # twitter
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


def get_image_url_checker():
    """Search for an image that was uploaded, so the url can be checked for a date.

    It is an edge case that the items that are not otherwise identified have
    <meta property="og:image" content="//wp-content/uploads/2015/03/something.jpg" />
    """
    return _make_tag_checker({'property': 'og:image'})
