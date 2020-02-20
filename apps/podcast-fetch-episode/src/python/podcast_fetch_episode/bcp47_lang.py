from typing import Optional
from urllib.parse import urlparse

from mediawords.util.log import create_logger
from mediawords.util.url import fix_common_url_mistakes, canonical_url

log = create_logger(__name__)


def _country_tld_from_url(url: str) -> Optional[str]:
    """
    Extract country TLD from URL; it's URL looks weird, don't sweat about it.

    :param url: URL, e.g. "https://www.bbc.co.uk/news/politics/eu-regions/vote2014_sitemap.xml".
    :return: Country TLD of URL without the prefix period, e.g. "uk", or None if there's no TLD.
    """
    if not url:
        return None

    url = fix_common_url_mistakes(url)

    try:
        url = canonical_url(url)
    except Exception as ex:
        log.error(f"Unable to get canonical URL from URL {url}: {ex}")
        return None

    try:
        parsed_url = urlparse(url)
    except Exception as ex:
        log.warning(f"Unable to parse URL {url}: {ex}")
        return None

    hostname_parts = parsed_url.hostname.split('.')

    if len(hostname_parts) < 2:
        log.warning(f"No TLD found in URL {url}")
        return None

    return hostname_parts[-1].lower()


def iso_639_1_code_to_bcp_47_identifier(iso_639_1_code: str, url_hint: Optional[str] = None) -> Optional[str]:
    """
    Convert ISO 639-1 language code to BCP-47 identifier.

    Google Cloud requires for us to pass the language as a BCP-47 identifier:

    https://cloud.google.com/speech-to-text/docs/languages

    so we have to do some guessing about the dialect the audio data is going to be in.

    :param iso_639_1_code: ISO 639-1 language code, e.g. "en".
    :param url_hint: Optional URL hint to use for guessing the dialect used.
    :return: BCP-47 identifier, e.g. "en-US", or None if the identifier can't be determined.
    """

    if not iso_639_1_code:
        log.warning("ISO 639-1 code is unset.")
        return None

    tld = None
    if url_hint:
        tld = _country_tld_from_url(url_hint)

    iso_639_1_code = iso_639_1_code.lower()

    if iso_639_1_code in {
        # Language == country.upper()
        'de',
        'hr',
        'is',
        'it',
        'lv',
        'lt',
        'hu',
        'nl',
        'pl',
        'ro',
        'sk',
        'sl',
        'fi',
        'tr',
        'bg',
        'ru',
        'th',
    }:
        return f"{iso_639_1_code}-{iso_639_1_code.upper()}"

    elif iso_639_1_code in {
        # Languages in India
        'gu',
        'gn',
        'ml',
        'mr',
    }:
        return f"{iso_639_1_code}-IN"

    elif iso_639_1_code == 'af':
        return 'af-ZA'

    elif iso_639_1_code == 'am':
        return 'am-ET'

    elif iso_639_1_code == 'hy':
        return 'hy-AM'

    elif iso_639_1_code == 'az':
        return 'az-AZ'

    elif iso_639_1_code == 'id':
        return 'id-ID'

    elif iso_639_1_code == 'ms':
        return 'ms-MY'

    elif iso_639_1_code == 'bn':

        if tld == 'in':
            return 'bn-IN'

        # Fallback
        return 'bn-BD'

    elif iso_639_1_code == 'ca':
        return 'ca-ES'

    elif iso_639_1_code == 'cs':
        return 'cs-CZ'

    elif iso_639_1_code == 'da':
        return 'da-DK'

    elif iso_639_1_code == 'en':

        if tld == 'uk':
            return 'en-GB'

        elif tld in {
            'au',
            'ca',
            'gh',
            'in',
            'ie',
            'ke',
            'nz',
            'ng',
            'ph',
            'sg',
            'za',
            'tz',
        }:
            return f'en-{tld.upper()}'

        # Fallback
        return 'en-US'

    elif iso_639_1_code == 'es':

        if tld in {
            'ar',
            'bo',
            'cl',
            'co',
            'cr',
            'ec',
            'sv',
            'es',
            'us',
            'gt',
            'hn',
            'mx',
            'ni',
            'pa',
            'py',
            'pe',
            'pr',
            'do',
            'uy',
            've',
        }:
            return f'es-{tld.upper()}'

        # Fallback
        return 'es-ES'

    elif iso_639_1_code == 'eu':
        return 'eu-ES'

    elif iso_639_1_code == 'fil':
        return 'fil-PH'

    elif iso_639_1_code == 'fr':
        if tld == 'ca':
            return 'fr-CA'

        return 'fr-FR'

    elif iso_639_1_code == 'gl':
        return 'gl-ES'

    elif iso_639_1_code == 'ka':
        return 'ka-GE'

    elif iso_639_1_code == 'zu':
        return 'zu-ZA'

    elif iso_639_1_code == 'jv':
        return 'jv-ID'

    elif iso_639_1_code == 'km':
        return 'km-KH'

    elif iso_639_1_code == 'lo':
        return 'lo-LA'

    elif iso_639_1_code == 'ne':
        return 'ne-NP'

    elif iso_639_1_code == 'nb':
        return 'nb-NO'

    elif iso_639_1_code == 'pt':
        if tld == 'br':
            return 'pt-BR'

        # Fallback
        return 'pt-PT'

    elif iso_639_1_code == 'si':
        return 'si-LK'

    elif iso_639_1_code == 'su':
        return 'su-ID'

    elif iso_639_1_code == 'sw':
        if tld == 'tz':
            return 'sw-TZ'

        # Fallback
        return 'sw-KE'

    elif iso_639_1_code == 'sv':
        return 'sv-SE'

    elif iso_639_1_code == 'ta':
        if tld in {
            'sg',
            'lk',
            'my',
        }:
            return f'ta-{tld.upper()}'

        # Fallback
        return 'ta-IN'

    elif iso_639_1_code == 'te':
        return 'te-IN'

    elif iso_639_1_code == 'vi':
        return 'vi-VN'

    elif iso_639_1_code == 'ur':
        if tld == 'pk':
            return 'ur-PK'

        # Fallback -- more Urdu speakers in India than Pakistan
        return 'ur-IN'

    elif iso_639_1_code == 'el':
        return 'el-GR'

    elif iso_639_1_code == 'sr':
        return 'sr-RS'

    elif iso_639_1_code == 'uk':
        return 'uk-UA'

    elif iso_639_1_code == 'he':
        return 'he-IL'

    elif iso_639_1_code == 'ar':

        if tld in {
            'il',
            'jo',
            'ae',
            'bh',
            'dz',
            'sa',
            'iq',
            'kw',
            'ma',
            'tn',
            'om',
            'ps',
            'qa',
            'lb',
        }:
            return f'ar-{tld.upper()}'

        # Fallback -- Egyptian Arabic is the most popular dialect
        return 'ar-EG'

    elif iso_639_1_code == 'hi':
        return 'hi-IN'

    elif iso_639_1_code == 'ko':
        return 'ko-KR'

    # Chinese (simplified)
    elif iso_639_1_code == 'zh' or iso_639_1_code == 'zh-Hans':
        if tld == 'hk':
            return 'zh-HK'

        # Fallback
        return 'zh'

    # Chinese (traditional)
    elif iso_639_1_code == 'yue' or iso_639_1_code == 'zh-Hant':
        if tld == 'tw':
            return 'zh-TW'

        # Fallback
        return 'yue-Hant-HK'

    elif iso_639_1_code == 'ja':
        return 'ja-JP'

    return None
