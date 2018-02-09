from http import HTTPStatus
import re
from urllib.parse import urlparse

import requests


def generate_date_string_range(start_date, end_date):
    """Generate YYYY-MM format from start_date to end_date, inclusive

    Parameters
    ----------
    start_date : str
        YYYY-MM format to start at

    end_date : str
        YYYY-MM format to end at

    Returns
    -------
    List of strings in format YYYY-MM-01 from the start to the end date
    """
    year, month = map(int, start_date.split('-'))
    current = start_date
    dates = ['{}-01'.format(current)]
    while dates[-1] < end_date:
        year_change, month = divmod(month, 12)
        year += year_change
        month += 1
        dates.append('{:04}-{:02}-01'.format(year, month))
    return dates


class SimilarWebClient(object):
    url = 'https://api.similarweb.com/v1/website/{}/total-traffic-and-engagement/visits'
    describe_url = 'https://api.similarweb.com/v1/website/foo/total-traffic-and-engagement/describe'

    def __init__(self, api_key):
        """Initialize client with an API key.

        Reuse this if possible to reuse the max date range we may query.

        Parameters:
        -----------
            api_key : str
                Available from SimilarWeb
        """
        self.api_key = api_key
        self._start_date = None
        self._end_date = None

    def _set_max_date_range(self):
        """SimilarWeb allows for a certain date range at a given time, this finds the max"""
        resp = self.make_get_request(self.describe_url, {'api_key': self.api_key})
        resp.raise_for_status()
        data = resp.json()
        try:
            dates = data['response']['total_traffic_and_engagement']['countries']['world']
        except KeyError:
            raise KeyError("Expected keys 'response', 'total_traffic_and_engagement', 'countries', 'world', "
                           "got object {} instead.".format(str(data)))
        self._start_date = dates['start_date']
        self._end_date = dates['end_date']

    @property
    def end_date(self):
        """Look this up at run time"""
        if self._end_date is None:
            self._set_max_date_range()
        return self._end_date

    @property
    def start_date(self):
        """Look this up at run time"""
        if self._start_date is None:
            self._set_max_date_range()
        return self._start_date

    def make_params(self, **kwargs):
        """Create the query parameter dictionary for a SimilarWeb API call

        Parameters:
        -----------
        kwargs :
            Named keyword arguments are added to the request

        Returns:
        --------
        Dictionary that may be passed as query parameters to SimilarWeb
        """
        query_args = {
            'start_date': self.start_date,
            'end_date': self.end_date,
            'api_key': self.api_key,
            'main_domain_only': 'false',
            'granularity': 'monthly',
        }
        query_args.update(kwargs)
        return query_args

    @staticmethod
    def tidy_url(url):
        """Cleans up a url just a little, and removes the initial www (or similar)

        Parameters
        ----------
        url : str
            URL to lightly clean. Perhaps to check for an exact match?

        Returns
        -------
        str, lightly cleaned url
        """
        tidied = url.lower().strip('/ ')
        return re.sub(r'(www[0-9]*|m)\.', '', tidied)

    @staticmethod
    def get_domain(url):
        """Edit URL to make it appropriate for SimilarWeb API

        SimilarWeb only works on the netloc, with no www.

        Parameters
        ----------
        url : str
            URL to turn into a query for SimilarWeb

        Returns
        -------
            str: the domain of url
        """
        return SimilarWebClient.tidy_url(urlparse(url).netloc)

    def make_get_request(self, url, params):
        """Makes API call to SimilarWeb.

        This is a wrapper to allow different methods to make the actual HTTP requests

        Parameters
        ----------
            url : str
                URL to make a GET request to
            params : dict
                Query parameters to send along as well

        Returns
        -------
        requests.Response
        """
        return requests.get(url, params=params)

    def prepare_similarweb_url(self, domain):
        """Constructs URL to request similarweb data for.

        Parameters
        ----------
            domain : str
                URL to request data for

        Returns
        -------
            str, proper URL for similarweb request
        """
        prepared_domain = self.get_domain(domain)
        return self.url.format(prepared_domain)

    def get(self, domain, **query_args):
        """Fetches data from SimilarWeb for the given domain

        Note that the domain is "normalized" to make sure SimilarWeb might accept it. In order to
        inspect the normalization, see the SimilarWebClient.get_domain method.

        Parameters
        ----------
            domain : str
                URL to request data for
            start_date: str
                in format YYYY-MM
            end_date: str
                in format YYYY-MM
            query_args: kwargs
                passed to the request as query arguments

        Returns
        -------
            dict, results from SimilarWeb
        """
        params = self.make_params(**query_args)
        resp = self.make_get_request(self.prepare_similarweb_url(domain), params)
        if resp.status_code == HTTPStatus.NOT_FOUND:
            data = resp.json()
            data['visits'] = [{'visits': None, 'date': date} for date in
                              generate_date_string_range(self.start_date, self.end_date)]
            data['status'] = 'Success'
            return data
        resp.raise_for_status()
        return resp.json()
