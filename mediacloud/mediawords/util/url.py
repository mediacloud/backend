import re
from urllib.parse import urlparse, parse_qs, urlsplit, urlunsplit, urlencode
import url_normalize

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_string_from_bytes_if_needed

l = create_logger(__name__)

# URL regex (http://stackoverflow.com/a/7160778/200603)
__URL_REGEX = re.compile(
    r'^(?:http|ftp)s?://'  # http:// or https://
    r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+(?:[A-Z]{2,6}\.?|[A-Z0-9-]{2,}\.?)|'  # domain...
    r'localhost|'  # localhost...
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # ...or ip
    r'(?::\d+)?'  # optional port
    r'(?:/?|[/?]\S+)$', re.IGNORECASE)

# Regular expressions for URL's path that, when matched, mean that the URL is a homepage URL
__HOMEPAGE_URL_PATH_REGEXES = [

    # Empty path (e.g. http://www.nytimes.com)
    re.compile(r'^$', re.I),

    # One or more slash (e.g. http://www.nytimes.com/, http://m.wired.com///)
    re.compile(r'^/+$', re.I),

    # Limited number of either all-lowercase or all-uppercase (but not both)
    # characters and no numbers, e.g.:
    #
    # * /en/,
    # * /US
    # * /global/,
    # * /trends/explore
    #
    # but not:
    #
    # * /oKyFAMiZMbU
    # * /1uSjCJp
    re.compile(r'^[a-z/\-_]{1,18}/?$'),
    re.compile(r'^[A-Z/\-_]{1,18}/?$'),
]

# URL shortener hostnames
#
# Sources:
# * http://www.techmaish.com/list-of-230-free-url-shorteners-services/
# * http://longurl.org/services
__URL_SHORTENER_HOSTNAMES = [
    '0rz.tw',
    '1link.in',
    '1url.com',
    '2.gp',
    '2big.at',
    '2pl.us',
    '2tu.us',
    '2ya.com',
    '3.ly',
    '307.to',
    '4ms.me',
    '4sq.com',
    '4url.cc',
    '6url.com',
    '7.ly',
    'a.gg',
    'a.nf',
    'a2a.me',
    'aa.cx',
    'abbrr.com',
    'abcurl.net',
    'ad.vu',
    'adf.ly',
    'adjix.com',
    'afx.cc',
    'all.fuseurl.com',
    'alturl.com',
    'amzn.to',
    'ar.gy',
    'arst.ch',
    'atu.ca',
    'azc.cc',
    'b23.ru',
    'b2l.me',
    'bacn.me',
    'bcool.bz',
    'binged.it',
    'bit.ly',
    'bizj.us',
    'bkite.com',
    'bloat.me',
    'bravo.ly',
    'bsa.ly',
    'budurl.com',
    'buk.me',
    'burnurl.com',
    'c-o.in',
    'canurl.com',
    'chilp.it',
    'chzb.gr',
    'cl.lk',
    'cl.ly',
    'clck.ru',
    'cli.gs',
    'cliccami.info',
    'clickmeter.com',
    'clickthru.ca',
    'clop.in',
    'conta.cc',
    'cort.as',
    'cot.ag',
    'crks.me',
    'ctvr.us',
    'cutt.us',
    'cuturl.com',
    'dai.ly',
    'decenturl.com',
    'dfl8.me',
    'digbig.com',
    'digg.com',
    'disq.us',
    'dld.bz',
    'dlvr.it',
    'do.my',
    'doiop.com',
    'dopen.us',
    'dwarfurl.com',
    'dy.fi',
    'easyuri.com',
    'easyurl.net',
    'eepurl.com',
    'esyurl.com',
    'eweri.com',
    'ewerl.com',
    'fa.b',
    'fa.by',
    'fav.me',
    'fb.me',
    'fbshare.me',
    'ff.im',
    'fff.to',
    'fhurl.com',
    'fire.to',
    'firsturl.de',
    'firsturl.net',
    'flic.kr',
    'flq.us',
    'fly2.ws',
    'fon.gs',
    'freak.to',
    'fuseurl.com',
    'fuzzy.to',
    'fwd4.me',
    'fwib.net',
    'g.ro.lt',
    'gizmo.do',
    'gl.am',
    'go.9nl.com',
    'go.ign.com',
    'go.usa.gov',
    'go2.me',
    'go2cut.com',
    'goo.gl',
    'goshrink.com',
    'gowat.ch',
    'gri.ms',
    'gurl.es',
    'hellotxt.com',
    'hex.io',
    'hiderefer.com',
    'hmm.ph',
    'hover.com',
    'href.in',
    'hsblinks.com',
    'htxt.it',
    'huff.to',
    'hugeurl.com',
    'hulu.com',
    'hurl.it',
    'hurl.me',
    'hurl.ws',
    'icanhaz.com',
    'idek.net',
    'ilix.in',
    'inreply.to',
    'is.gd',
    'iscool.net',
    'iterasi.net',
    'its.my',
    'ix.lt',
    'j.mp',
    'jijr.com',
    'jmp2.net',
    'just.as',
    'kissa.be',
    'kl.am',
    'klck.me',
    'korta.nu',
    'krunchd.com',
    'l9k.net',
    'lat.ms',
    'liip.to',
    'liltext.com',
    'lin.cr',
    'linkbee.com',
    'linkbun.ch',
    'liurl.cn',
    'ln-s.net',
    'ln-s.ru',
    'lnk.gd',
    'lnk.in',
    'lnk.ms',
    'lnkd.in',
    'lnkurl.com',
    'loopt.us',
    'lru.jp',
    'lt.tl',
    'lurl.no',
    'macte.ch',
    'mash.to',
    'merky.de',
    'metamark.net',
    'migre.me',
    'minilien.com',
    'miniurl.com',
    'minurl.fr',
    'mke.me',
    'moby.to',
    'moourl.com',
    'mrte.ch',
    'myloc.me',
    'myurl.in',
    'n.pr',
    'nbc.co',
    'nblo.gs',
    'ne1.net',
    'njx.me',
    'nn.nf',
    'not.my',
    'notlong.com',
    'nsfw.in',
    'nutshellurl.com',
    'nxy.in',
    'nyti.ms',
    'o-x.fr',
    'oc1.us',
    'om.ly',
    'omf.gd',
    'omoikane.net',
    'on.cnn.com',
    'on.mktw.net',
    'onforb.es',
    'orz.se',
    'ow.ly',
    'pd.am',
    'pic.gd',
    'ping.fm',
    'piurl.com',
    'pli.gs',
    'pnt.me',
    'politi.co',
    'poprl.com',
    'post.ly',
    'posted.at',
    'pp.gg',
    'profile.to',
    'ptiturl.com',
    'pub.vitrue.com',
    'qicute.com',
    'qlnk.net',
    'qte.me',
    'qu.tc',
    'quip-art.com',
    'qy.fi',
    'r.im',
    'rb6.me',
    'read.bi',
    'readthis.ca',
    'reallytinyurl.com',
    'redir.ec',
    'redirects.ca',
    'redirx.com',
    'retwt.me',
    'ri.ms',
    'rickroll.it',
    'riz.gd',
    'rsmonkey.com',
    'rt.nu',
    'ru.ly',
    'rubyurl.com',
    'rurl.org',
    'rww.tw',
    's4c.in',
    's7y.us',
    'safe.mn',
    'sameurl.com',
    'sdut.us',
    'shar.es',
    'sharein.com',
    'sharetabs.com',
    'shink.de',
    'shorl.com',
    'short.ie',
    'short.to',
    'shortlinks.co.uk',
    'shortna.me',
    'shorturl.com',
    'shoturl.us',
    'shout.to',
    'show.my',
    'shrinkify.com',
    'shrinkr.com',
    'shrinkster.com',
    'shrt.fr',
    'shrt.st',
    'shrten.com',
    'shrunkin.com',
    'shw.me',
    'simurl.com',
    'slate.me',
    'smallr.com',
    'smsh.me',
    'smurl.name',
    'sn.im',
    'snipr.com',
    'snipurl.com',
    'snurl.com',
    'sp2.ro',
    'spedr.com',
    'sqrl.it',
    'srnk.net',
    'srs.li',
    'starturl.com',
    'sturly.com',
    'su.pr',
    'surl.co.uk',
    'surl.hu',
    't.cn',
    't.co',
    't.lh.com',
    'ta.gd',
    'tbd.ly',
    'tcrn.ch',
    'tgr.me',
    'tgr.ph',
    'thrdl.es',
    'tighturl.com',
    'tiniuri.com',
    'tiny.cc',
    'tiny.ly',
    'tiny.pl',
    'tiny123.com',
    'tinyarro.ws',
    'tinylink.in',
    'tinytw.it',
    'tinyuri.ca',
    'tinyurl.com',
    'tinyvid.io',
    'tk.',
    'tl.gd',
    'tmi.me',
    'tnij.org',
    'tnw.to',
    'tny.com',
    'to.',
    'to.ly',
    'togoto.us',
    'totc.us',
    'toysr.us',
    'tpm.ly',
    'tr.im',
    'tr.my',
    'tra.kz',
    'traceurl.com',
    'trunc.it',
    'turo.us',
    'tweetburner.com',
    'twhub.com',
    'twirl.at',
    'twit.ac',
    'twitclicks.com',
    'twitterpan.com',
    'twitterurl.net',
    'twitterurl.org',
    'twitthis.com',
    'twiturl.de',
    'twurl.cc',
    'twurl.nl',
    'u.mavrev.com',
    'u.nu',
    'u6e.de',
    'u76.org',
    'ub0.cc',
    'ulu.lu',
    'updating.me',
    'ur1.ca',
    'url.az',
    'url.co.uk',
    'url.ie',
    'url360.me',
    'url4.eu',
    'urlao.com',
    'urlborg.com',
    'urlbrief.com',
    'urlcover.com',
    'urlcut.com',
    'urlenco.de',
    'urlhawk.com',
    'urli.nl',
    'urlkiss.com',
    'urlot.com',
    'urlpire.com',
    'urls.im',
    'urlshorteningservicefortwitter.com',
    'urlx.ie',
    'urlx.org',
    'urlzen.com',
    'usat.ly',
    'use.my',
    'vb.ly',
    'vgn.am',
    'virl.com',
    'vl.am',
    'vm.lc',
    'w3t.org',
    'w55.de',
    'wapo.st',
    'wapurl.co.uk',
    'wipi.es',
    'wp.me',
    'x.se',
    'x.vu',
    'xaddr.com',
    'xeeurl.com',
    'xr.com',
    'xrl.in',
    'xrl.us',
    'xurl.es',
    'xurl.jp',
    'xzb.cc',
    'y.ahoo.it',
    'yatuc.com',
    'ye.pe',
    'yep.it',
    'yfrog.com',
    'yhoo.it',
    'yiyd.com',
    'youtu.be',
    'yuarel.com',
    'yweb.com',
    'z0p.de',
    'zi.ma',
    'zi.mu',
    'zi.pe',
    'zipmyurl.com',
    'zud.me',
    'zurl.ws',
    'zz.gd',
    'zzang.kr',
    '›.ws',
    '✩.ws',
    '✿.ws',
    '❥.ws',
    '➔.ws',
    '➞.ws',
    '➡.ws',
    '➨.ws',
    '➯.ws',
    '➹.ws',
    '➽.ws',
]


def fix_common_url_mistakes(url):
    """Fixes common URL mistakes (mistypes, etc.)."""
    url = decode_string_from_bytes_if_needed(url)

    if url is None:
        return None

    # Fix broken URLs that look like this: http://http://www.al-monitor.com/pulse
    url = re.sub(r'(https?://)https?:?//', r"\1", url, flags=re.I)

    # Fix URLs with only one slash after "http" ("http:/www.")
    url = re.sub(r'(https?:/)(www)', r"\1/\2", url, flags=re.I)

    # replace backslashes with forward
    url = re.sub(r'\\', r'/', url)

    # http://newsmachete.com?page=2 -> http://newsmachete.com/?page=2
    url = re.sub(r'(https?://[^/]+)\?', r"\1/?", url)

    return url


def is_http_url(url):
    """Returns true if URL is in the "http" ("https") scheme."""
    url = decode_string_from_bytes_if_needed(url)
    if url is None:
        l.debug("URL is None")
        return False
    if len(url) == 0:
        l.debug("URL is empty")
        return False
    if not re.search(__URL_REGEX, url):
        l.debug("URL '%s' does not match URL's regexp" % url)
        return False

    uri = urlparse(url)

    if not uri.scheme:
        l.debug("Scheme is undefined for URL %s" % url)
        return False
    if not uri.scheme.lower() in ['http', 'https']:
        l.debug("Scheme is not HTTP(s) for URL %s" % url)
        return False

    return True


def is_shortened_url(url):
    """Returns true if URL is a shortened URL (e.g. with Bit.ly)."""
    url = decode_string_from_bytes_if_needed(url)
    if url is None:
        l.debug("URL is None")
        return False
    if len(url) == 0:
        l.debug("URL is empty")
        return False
    if not is_http_url(url):
        l.debug("URL is not valid")
        return False

    uri = urlparse(url)

    if uri.path is not None and uri.path in ['', '/']:
        # Assume that most of the URL shorteners use something like
        # bit.ly/abcdef, so if there's no path or if it's empty, it's not a
        # shortened URL
        return False

    uri_host = uri.hostname.lower()
    if uri_host in __URL_SHORTENER_HOSTNAMES:
        return True

    return False


def __canonical_url(url):
    """Make URL canonical (lowercase scheme and host, remove default port, etc.)"""
    return url_normalize.url_normalize(url)


class NormalizeURLException(Exception):
    pass


def normalize_url(url):
    """Normalize URL

    * Fix common mistypes, e.g. "http://http://..."
    * Run URL through normalization, i.e. standardize URL's scheme and hostname case, remove default port, uppercase
      all escape sequences, unescape octets that can be represented as plain characters, remove whitespace before /
      after the URL string)
    * Remove #fragment
    * Remove various ad tracking query parameters, e.g. "utm_source", "utm_medium", "PHPSESSID", etc.

    Return normalized URL on success; raise on error"""
    url = decode_string_from_bytes_if_needed(url)
    if url is None:
        raise NormalizeURLException("URL is None")
    if len(url) == 0:
        raise NormalizeURLException("URL is empty")

    url = fix_common_url_mistakes(url)
    url = __canonical_url(url)

    if not is_http_url(url):
        raise NormalizeURLException("URL is not valid")

    scheme, netloc, path, query_string, fragment = urlsplit(url)
    query = parse_qs(query_string, keep_blank_values=True)

    # Remove #fragment
    fragment = ''

    parameters_to_remove = []

    # Facebook parameters (https://developers.facebook.com/docs/games/canvas/referral-tracking)
    parameters_to_remove += [
        'fb_action_ids',
        'fb_action_types',
        'fb_source',
        'fb_ref',
        'action_object_map',
        'action_type_map',
        'action_ref_map',
        'fsrc_fb_noscript',
    ]

    # metrika.yandex.ru parameters
    parameters_to_remove += [
        'yclid',
        '_openstat',
    ]

    if 'facebook.com' in netloc.lower():
        # Additional parameters specifically for the facebook.com host
        parameters_to_remove += [
            'ref',
            'fref',
            'hc_location',
        ]

    if 'nytimes.com' in netloc.lower():
        # Additional parameters specifically for the nytimes.com host
        parameters_to_remove += [
            'emc',
            'partner',
            '_r',
            'hp',
            'inline',
            'smid',
            'WT.z_sma',
            'bicmp',
            'bicmlukp',
            'bicmst',
            'bicmet',
            'abt',
            'abg',
        ]

    if 'livejournal.com' in netloc.lower():
        # Additional parameters specifically for the livejournal.com host
        parameters_to_remove += [
            'thread',
            'nojs',
        ]

    if 'google.' in netloc.lower():
        # Additional parameters specifically for the google.[com,lt,...] host
        parameters_to_remove += [
            'gws_rd',
            'ei',
        ]

    # Some other parameters (common for tracking session IDs, advertising, etc.)
    parameters_to_remove += [
        'PHPSESSID',
        'PHPSESSIONID',
        'cid',
        's_cid',
        'sid',
        'ncid',
        'ir',
        'ref',
        'oref',
        'eref',
        'ns_mchannel',
        'ns_campaign',
        'ITO',
        'wprss',
        'custom_click',
        'source',
        'feedName',
        'feedType',
        'skipmobile',
        'skip_mobile',
        'altcast_code',
    ]

    # Make the sorting default (e.g. on Reddit)
    # Some other parameters (common for tracking session IDs, advertising, etc.)
    parameters_to_remove += ['sort']

    # Some Australian websites append the "nk" parameter with a tracking hash
    if 'nk' in query:
        for nk_value in query['nk']:
            if re.search(r'^[0-9a-fA-F]+$', nk_value, re.I):
                parameters_to_remove += ['nk']
                break

    # Delete the "empty" parameter (e.g. in http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6)
    parameters_to_remove += ['']

    # Remove cruft parameters
    for parameter in parameters_to_remove:
        if ' ' in parameter:
            l.warn('Invalid cruft parameter "%s"' % parameter)
        query.pop(parameter, None)

    for name in list(query.keys()):  # copy of list to be able to delete

        # Remove parameters that start with '_' (e.g. '_cid') because they're
        # more likely to be the tracking codes
        if name.startswith('_'):
            query.pop(name)

        # Remove GA parameters, current and future (e.g. "utm_source",
        # "utm_medium", "ga_source", "ga_medium")
        # (https://support.google.com/analytics/answer/1033867?hl=en)
        if name.startswith('ga_') or name.startswith('utm_'):
            query.pop(name)

    url = urlunsplit((scheme, netloc, path, urlencode(query, doseq=True), fragment))

    # Remove empty values in query string, e.g. http://bash.org/?244321=
    url = url.replace('=&', '&')
    url = re.sub(r'=$', '', url)

    return url


def normalize_url_lossy(url):
    """Do some simple transformations on a URL to make it match other equivalent URLs as well as possible; normalization
    is "lossy" (makes the whole URL lowercase, removes subdomain parts "m.", "data.", "news.", ... in some cases)"""
    url = decode_string_from_bytes_if_needed(url)
    if url is None:
        return None
    if len(url) == 0:
        return None

    url = fix_common_url_mistakes(url)

    url = url.lower()

    # r2.ly redirects through the hostname, ala http://543.r2.ly
    if 'r2.ly' not in url:
        url = re.sub(
            r'^(https?://)(m|beta|media|data|image|www?|cdn|topic|article|news|archive|blog|video|search|preview|'
            + 'shop|sports?|act|donate|press|web|photos?|\d+?).?\.(.*\.)',
            r"\1\3", url, re.I)

    # collapse the vast array of http://pronkraymond83483.podomatic.com/ urls into http://pronkpops.podomatic.com/
    url = re.sub(r'http://.*pron.*\.podomatic\.com', 'http://pronkpops.podomatic.com', url)

    # get rid of anchor text
    url = re.sub(r'#.*', '', url)

    # get rid of multiple slashes in a row
    url = re.sub(r'(//.*/)/+', r"\1", url)

    url = re.sub(r'^https:', 'http:', url)

    url = __canonical_url(url)

    # add trailing slash
    if re.search(r'https?://[^/]*$', url):
        url += '/'

    return url


def is_homepage_url(url):
    """Returns true if URL is homepage (e.g. http://www.wired.com/) and not a child page
    (e.g. http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/)."""
    url = decode_string_from_bytes_if_needed(url)
    if url is None:
        l.debug("URL is None.")
        return False
    if len(url) == 0:
        l.debug("URL is empty.")
        return False

    if not is_http_url(url):
        l.debug("URL '%s' is invalid." % url)
        return False

    # Remove cruft from the URL first
    try:
        url = normalize_url(url)
    except NormalizeURLException as ex:
        l.debug("Unable to normalize URL '%s' before checking if it's a homepage: %s" % (url, ex))
        return False

    # The shortened URL may lead to a homepage URL, but the shortened URL
    # itself is not a homepage URL
    if is_shortened_url(url):
        return False

    # If we still have something for a query of the URL after the
    # normalization, always assume that the URL is *not* a homepage
    scheme, netloc, uri_path, query_string, fragment = urlsplit(url)
    if len(query_string) > 0:
        return False

    for homepage_url_path_regex in __HOMEPAGE_URL_PATH_REGEXES:
        if re.search(homepage_url_path_regex, uri_path):
            return True

    return False


class GetURLHostException(Exception):
    pass


def get_url_host(url):
    """Return hostname of an URL."""
    url = decode_string_from_bytes_if_needed(url)
    if url is None:
        raise GetURLHostException("URL is None")
    if len(url) == 0:
        raise GetURLHostException("URL is empty")

    url = fix_common_url_mistakes(url)

    uri = urlparse(url)
    return uri.hostname
