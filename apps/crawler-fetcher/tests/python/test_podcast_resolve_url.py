from __future__ import print_function

import os
import sys
from collections import OrderedDict

import pytest

# noinspection PyProtectedMember
from crawler_fetcher.handlers.feed_podcast import (
    _get_feed_url_from_itunes_podcasts_url,
    _get_feed_url_from_google_podcasts_url,
)


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    # execute all other hooks to obtain the report object
    outcome = yield
    report = outcome.get_result()

    # enable only in a workflow of GitHub Actions
    # ref: https://help.github.com/en/actions/configuring-and-managing-workflows/using-environment-variables#default-environment-variables
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return

    if report.when == "call" and report.failed:
        # collect information to be annotated
        filesystempath, lineno, _ = report.location

        # try to convert to absolute path in GitHub Actions
        workspace = os.environ.get("GITHUB_WORKSPACE")
        if workspace:
            full_path = os.path.abspath(filesystempath)
            try:
                rel_path = os.path.relpath(full_path, workspace)
            except ValueError:
                # os.path.relpath() will raise ValueError on Windows
                # when full_path and workspace have different mount points.
                # https://github.com/utgwkk/pytest-github-actions-annotate-failures/issues/20
                rel_path = filesystempath
            if not rel_path.startswith(".."):
                filesystempath = rel_path

        # 0-index to 1-index
        lineno += 1

        # get the name of the current failed test, with parametrize info
        longrepr = report.head_line or item.name

        # get the error message and line number from the actual error
        try:
            longrepr += "\n\n" + report.longrepr.reprcrash.message
            lineno = report.longrepr.reprcrash.lineno

        except AttributeError:
            pass

        print(
            _error_workflow_command(filesystempath, lineno, longrepr), file=sys.stderr
        )


def _error_workflow_command(filesystempath, lineno, longrepr):
    # Build collection of arguments. Ordering is strict for easy testing
    details_dict = OrderedDict()
    details_dict["file"] = filesystempath
    if lineno is not None:
        details_dict["line"] = lineno

    details = ",".join("{}={}".format(k, v) for k, v in details_dict.items())

    if longrepr is None:
        return "\n::error {}".format(details)
    else:
        longrepr = _escape(longrepr)
        return "\n::error {}::{}".format(details, longrepr)


def _escape(s):
    return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def test_get_feed_url_from_itunes_podcasts_url():
    # noinspection PyTypeChecker
    assert _get_feed_url_from_itunes_podcasts_url(None) is None
    assert _get_feed_url_from_itunes_podcasts_url('') == ''
    assert _get_feed_url_from_itunes_podcasts_url('http://www.example.com/') == 'http://www.example.com/'
    assert _get_feed_url_from_itunes_podcasts_url('totally not an URL') == 'totally not an URL'

    # Let's just kind of hope RA doesn't change their underlying feed URL
    ra_feed_url = 'https://ra.co/xml/podcast.xml'

    ra_itunes_url = 'https://podcasts.apple.com/lt/podcast/ra-podcast/id129673441'
    assert _get_feed_url_from_itunes_podcasts_url(ra_itunes_url) == ra_feed_url

    # Try uppercase host
    ra_itunes_url = 'https://PODCASTS.APPLE.COM/lt/podcast/ra-podcast/id129673441'
    assert _get_feed_url_from_itunes_podcasts_url(ra_itunes_url) == ra_feed_url

    # Try old style URL
    ra_itunes_url = 'https://itunes.apple.com/lt/podcast/ra-podcast/id129673441'
    assert _get_feed_url_from_itunes_podcasts_url(ra_itunes_url) == ra_feed_url


def test_get_feed_url_from_google_podcasts_url():
    # noinspection PyTypeChecker
    assert _get_feed_url_from_google_podcasts_url(None) is None
    assert _get_feed_url_from_google_podcasts_url('') == ''
    assert _get_feed_url_from_google_podcasts_url('http://www.example.com/') == 'http://www.example.com/'
    assert _get_feed_url_from_google_podcasts_url('totally not an URL') == 'totally not an URL'

    npr_feed_url = 'https://feeds.npr.org/381444908/podcast.xml'

    # Test with URL pointing to a show's homepage (not invidual episode)

    npr_google_show_url = (
        'https://podcasts.google.com/feed/aHR0cHM6Ly9mZWVkcy5ucHIub3JnLzM4MTQ0NDkwOC9wb2RjYXN0LnhtbA?sa=X'
        '&ved=2ahUKEwjKm6fimbjuAhWMjoQIHUrSCW0Qjs4CKAl6BAgBEH4'
    )

    assert _get_feed_url_from_google_podcasts_url(npr_google_show_url) == npr_feed_url

    # Test with URL that points to a specific episode
    npr_google_ep_url = (
        'https://podcasts.google.com/feed/aHR0cHM6Ly9mZWVkcy5ucHIub3JnLzM4MTQ0NDkwOC9wb2RjYXN0LnhtbA/episode/'
        'MjA5MmZjM2ItYmMwZi00NGFiLWFlNDktM2I3YmFhMjA4ODVi?sa=X&ved=0CAUQkfYCahcKEwjg4s3umbjuAhUAAAAAHQAAAAAQAQ'
    )

    # assert _get_feed_url_from_google_podcasts_url(npr_google_ep_url) == npr_feed_url
    assert _get_feed_url_from_google_podcasts_url(npr_google_ep_url) != npr_feed_url
