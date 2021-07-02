import collections
import re
from typing import List, Pattern, Optional, Union

from mediawords.util.config import env_value, McConfigException
from mediawords.util.parse_json import decode_json, McDecodeJSONException
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.log import create_logger

log = create_logger(__name__)


class ConnectRetriesConfig(object):
    """Connect retries configuration."""

    __slots__ = [
        '__sleep_between_attempts',
        '__max_attempts',
        '__fatal_error_on_failure',
    ]

    def __init__(self,
                 sleep_between_attempts: float = 1.0,
                 max_attempts: int = 60,
                 fatal_error_on_failure: bool = True):

        if isinstance(sleep_between_attempts, bytes):
            sleep_between_attempts = decode_object_from_bytes_if_needed(sleep_between_attempts)
        if isinstance(max_attempts, bytes):
            max_attempts = decode_object_from_bytes_if_needed(max_attempts)
        if isinstance(fatal_error_on_failure, bytes):
            fatal_error_on_failure = decode_object_from_bytes_if_needed(fatal_error_on_failure)

        self.__sleep_between_attempts = float(sleep_between_attempts)
        self.__max_attempts = int(max_attempts)
        self.__fatal_error_on_failure = bool(fatal_error_on_failure)

    def sleep_between_attempts(self) -> float:
        """Seconds (or parts of second) to sleep between retries."""
        return self.__sleep_between_attempts

    def max_attempts(self) -> int:
        """Max. number of attempts to connect.

        Must be positive (we want to try connecting at least one time).
        """
        return self.__max_attempts

    def fatal_error_on_failure(self) -> bool:
        """
        Return True if connect_to_db() should call fatal_error() and thus stop the whole process when giving up.

        True is a useful value in production when you might want the process that's unable to connect to the database to
        just die. However, you might choose to return False here too if the caller is prepared to handle connection
        failures more gracefully (e.g. Temporal's retries).
        """
        return self.__fatal_error_on_failure


class DatabaseConfig(object):
    """PostgreSQL database configuration."""

    __slots__ = [
        '__hostname',
        '__port',
        '__database_name',
        '__username',
        '__password',
        '__retries',
    ]

    def __init__(self,
                 hostname: str = 'postgresql-pgbouncer',
                 port: int = 6432,
                 database_name: str = 'mediacloud',
                 username: str = 'mediacloud',
                 password: str = 'mediacloud',
                 retries: Optional[ConnectRetriesConfig] = None):
        if not retries:
            retries = ConnectRetriesConfig()

        if isinstance(port, bytes):
            port = decode_object_from_bytes_if_needed(port)

        hostname = decode_object_from_bytes_if_needed(hostname)
        database_name = decode_object_from_bytes_if_needed(database_name)
        username = decode_object_from_bytes_if_needed(username)
        password = decode_object_from_bytes_if_needed(password)

        self.__hostname = hostname
        self.__port = int(port)
        self.__database_name = database_name
        self.__username = username
        self.__password = password
        self.__retries = retries

    def hostname(self) -> str:
        """Hostname."""
        return self.__hostname

    def port(self) -> int:
        """Port."""
        return self.__port

    def database_name(self) -> str:
        """Database name."""
        return self.__database_name

    def username(self) -> str:
        """Username."""
        return self.__username

    def password(self) -> str:
        """Password."""
        return self.__password

    def retries(self) -> ConnectRetriesConfig:
        """connect_to_db() retries configuration."""
        return self.__retries


class AmazonS3DownloadsConfig(object):
    """Amazon S3 raw download storage configuration."""

    @staticmethod
    def access_key_id() -> str:
        """Access key ID."""
        return env_value('MC_DOWNLOADS_AMAZON_S3_ACCESS_KEY_ID')

    @staticmethod
    def secret_access_key() -> str:
        """Secret access key."""
        return env_value('MC_DOWNLOADS_AMAZON_S3_SECRET_ACCESS_KEY')

    @staticmethod
    def bucket_name() -> str:
        """Bucket name."""
        return env_value('MC_DOWNLOADS_AMAZON_S3_BUCKET_NAME')

    @staticmethod
    def directory_name() -> str:
        """Directory name (prefix)."""
        return env_value('MC_DOWNLOADS_AMAZON_S3_DIRECTORY_NAME', allow_empty_string=True)


class RabbitMQRetriesConfig(object):
    """
    RabbitMQ retries configuration.

    https://docs.celeryproject.org/en/v4.4.7/userguide/calling.html#calling-retry
    """

    __slots__ = [
        '__max_retries',
        '__interval_start',
        '__interval_step',
        '__interval_max',
    ]

    def __init__(self,
                 max_retries: Optional[int] = 3,
                 interval_start: Union[int, float] = 0,
                 interval_step: Union[int, float] = 0.2,
                 interval_max: Union[int, float] = 0.2):
        if isinstance(max_retries, bytes):
            max_retries = decode_object_from_bytes_if_needed(max_retries)
        if isinstance(interval_start, bytes):
            interval_start = decode_object_from_bytes_if_needed(interval_start)
        if isinstance(interval_step, bytes):
            interval_step = decode_object_from_bytes_if_needed(interval_step)
        if isinstance(interval_max, bytes):
            interval_max = decode_object_from_bytes_if_needed(interval_max)

        self.__max_retries = None if max_retries is None else int(max_retries)  # We want to preserve None here
        self.__interval_start = float(interval_start)
        self.__interval_step = float(interval_step)
        self.__interval_max = float(interval_max)

    def max_retries(self) -> Optional[int]:
        return self.__max_retries

    def interval_start(self) -> float:
        return self.__interval_start

    def interval_step(self) -> float:
        return self.__interval_step

    def interval_max(self) -> float:
        return self.__interval_max


class RabbitMQConfig(object):
    """RabbitMQ (Celery broker) client configuration."""

    __slots__ = [
        '__hostname',
        '__port',
        '__username',
        '__password',
        '__vhost',
        '__timeout',
        '__retries',
    ]

    def __init__(self,
                 hostname: str = 'rabbitmq-server',
                 port: int = 5672,
                 username: str = 'mediacloud',
                 password: str = 'mediacloud',
                 vhost: str = '/mediacloud',
                 timeout: int = 60,
                 retries: Optional[RabbitMQRetriesConfig] = None):
        hostname = decode_object_from_bytes_if_needed(hostname)
        if isinstance(port, bytes):
            port = decode_object_from_bytes_if_needed(port)
        username = decode_object_from_bytes_if_needed(username)
        password = decode_object_from_bytes_if_needed(password)
        vhost = decode_object_from_bytes_if_needed(vhost)
        if isinstance(timeout, bytes):
            timeout = decode_object_from_bytes_if_needed(timeout)

        self.__hostname = hostname
        self.__port = int(port)
        self.__username = username
        self.__password = password
        self.__vhost = vhost
        self.__timeout = int(timeout)
        self.__retries = retries

    def hostname(self) -> str:
        """Hostname."""
        return self.__hostname

    def port(self) -> int:
        """Port."""
        return self.__port

    def username(self) -> str:
        """Username."""
        return self.__username

    def password(self) -> str:
        """Password."""
        return self.__password

    def vhost(self) -> str:
        """Virtual host."""
        return self.__vhost

    def timeout(self) -> int:
        """Timeout."""
        return self.__timeout

    def retries(self) -> Optional[RabbitMQRetriesConfig]:
        """Retry policy; if None, retries are disabled."""
        return self.__retries


class SMTPConfig(object):
    """SMTP configuration."""

    @staticmethod
    def hostname() -> str:
        """Hostname."""
        # Container's name from docker-compose.yml
        return 'mail-postfix-server'

    @staticmethod
    def port() -> int:
        """Port."""
        # Container's exposed port from docker-compose.yml
        return 25

    @staticmethod
    def use_starttls() -> bool:
        """Use STARTTLS? If you enable that, you probably want to change the port to 587."""
        # FIXME remove altogether, not used
        return False

    @staticmethod
    def username() -> str:
        """Username."""
        # FIXME remove, not used
        return ''

    @staticmethod
    def password() -> str:
        """Password."""
        return ''

    @staticmethod
    def unsubscribe_address() -> str:
        """Email to which unsubscribe/account deletion requests should be sent"""
        address = env_value('MC_EMAIL_UNSUBSCRIBE', required=False, allow_empty_string=True)
        if address is None or '@' not in address:
            address = 'support@example.com'
        return address


class DownloadStorageConfig(object):
    """Download storage configuration."""

    @staticmethod
    def storage_locations() -> List[str]:
        """Download storage locations."""
        value = env_value('MC_DOWNLOADS_STORAGE_LOCATIONS', required=False)
        if value is None:
            value = 'postgresql'
        locations = value.split(';')
        locations = [location.strip() for location in locations]
        if len(locations) == 0 and locations[0] == '':
            locations = []
        return locations

    @staticmethod
    def read_all_from_s3() -> bool:
        """Whether or not to read all non-inline downloads from S3."""
        value = env_value('MC_DOWNLOADS_READ_ALL_FROM_S3', required=False, allow_empty_string=True)
        if value is None:
            value = 0
        return bool(int(value))

    @staticmethod
    def fallback_postgresql_to_s3() -> bool:
        """Whether to fallback PostgreSQL downloads to Amazon S3.

        If the download doesn't exist in PostgreSQL storage, S3 will be tried instead."""
        value = env_value('MC_DOWNLOADS_FALLBACK_POSTGRESQL_TO_S3', required=False, allow_empty_string=True)
        if value is None:
            value = 0
        return bool(int(value))

    @staticmethod
    def cache_s3() -> bool:
        """Whether to enable local Amazon S3 download cache."""
        value = env_value('MC_DOWNLOADS_CACHE_S3', required=False, allow_empty_string=True)
        if value is None:
            value = 0
        return bool(int(value))


class AuthenticatedDomain(object):
    """Single authenticated domain."""

    __slots__ = [
        '_domain',
        '_username',
        '_password',
    ]

    def __init__(self, domain: str, username: str, password: str):
        self._domain = domain
        self._username = username
        self._password = password

    def domain(self) -> str:
        """Return domain name, e.g. "ap.org"."""
        return self._domain

    def username(self) -> str:
        """Return HTTP auth username."""
        return self._username

    def password(self) -> str:
        """Return HTTP auth password."""
        return self._password

    # Tests do the comparison
    def __eq__(self, other) -> bool:
        if not isinstance(other, AuthenticatedDomain):
            return NotImplemented

        return (self.domain() == other.domain()) and (
                self.username() == other.username()) and (self.password() == other.password())

    # __eq__() disables hashing
    def __hash__(self):
        return hash((self._domain, self._username, self._password))


class McConfigAuthenticatedDomainsException(McConfigException):
    """Exception thrown on authenticated domains syntax errors."""
    pass


def _authenticated_domains_from_json(value: Optional[str]) -> List[AuthenticatedDomain]:
    """Parse the string and return a list of authenticated domains."""

    if value is None:
        return []

    value = value.strip()

    if not value:
        return []

    try:
        entries = decode_json(value)
    except McDecodeJSONException as ex:
        # Don't leak JSON errors to exception which might possibly end up in a public error message
        message = "Unable to decode authenticated domains."
        log.error(f"{message}: {ex}")
        raise McConfigAuthenticatedDomainsException(message)

    domains = []

    if not isinstance(entries, collections.Iterable):
        message = "Invalid JSON configuration"
        log.error(f"{message}: root is not an iterable (a list)")
        raise McConfigAuthenticatedDomainsException(message)

    for entry in entries:

        if not callable(getattr(entry, "get", None)):
            message = "Invalid JSON configuration"
            log.error(f"{message}: one of the items does not have get() (is not a dictionary)")
            raise McConfigAuthenticatedDomainsException(message)

        domain = entry.get('domain', None)
        username = entry.get('username', None)
        password = entry.get('password', None)

        if not (domain and username and password):
            raise McConfigAuthenticatedDomainsException("Incomplete authentication credentials.")

        domains.append(AuthenticatedDomain(domain=domain, username=username, password=password))

    return domains


class UserAgentConfig(object):
    """UserAgent configuration."""

    @staticmethod
    def blacklist_url_pattern() -> Optional[Pattern]:
        """URL pattern for which we should fail all of the HTTP(s) requests."""
        pattern = env_value('MC_USERAGENT_BLACKLIST_URL_PATTERN', required=False, allow_empty_string=True)
        if pattern:
            pattern = re.compile(pattern, flags=re.IGNORECASE | re.UNICODE)
        else:
            pattern = None
        return pattern

    @staticmethod
    def authenticated_domains() -> List[AuthenticatedDomain]:
        """List of authenticated domains."""
        value = env_value('MC_USERAGENT_AUTHENTICATED_DOMAINS', required=False, allow_empty_string=True)
        return _authenticated_domains_from_json(value)

    @staticmethod
    def parallel_get_num_parallel() -> int:
        """Parallel connection count."""
        value = env_value('MC_USERAGENT_PARALLEL_GET_NUM_PARALLEL', required=False)
        if value is None:
            value = 10
        return int(value)

    @staticmethod
    def parallel_get_timeout() -> int:
        """Connection timeout, in seconds."""
        value = env_value('MC_USERAGENT_PARALLEL_GET_TIMEOUT', required=False)
        if value is None:
            value = 90
        return int(value)

    @staticmethod
    def parallel_get_per_domain_timeout() -> int:
        """Per-domain timeout, in seconds."""
        value = env_value('MC_USERAGENT_PARALLEL_GET_PER_DOMAIN_TIMEOUT', required=False)
        if not value:
            value = 1
        return int(value)


class CommonConfig(object):
    """Global configuration (shared by all the apps)."""

    @staticmethod
    def database() -> DatabaseConfig:
        """PostgreSQL configuration."""
        return DatabaseConfig()

    @staticmethod
    def amazon_s3_downloads() -> AmazonS3DownloadsConfig:
        """Amazon S3 raw download storage configuration."""
        return AmazonS3DownloadsConfig()

    @staticmethod
    def rabbitmq() -> RabbitMQConfig:
        """RabbitMQ client configuration."""
        return RabbitMQConfig()

    @staticmethod
    def smtp() -> SMTPConfig:
        """SMTP configuration."""
        return SMTPConfig()

    @staticmethod
    def download_storage() -> DownloadStorageConfig:
        """Download storage configuration."""
        return DownloadStorageConfig()

    @staticmethod
    def user_agent() -> UserAgentConfig:
        """UserAgent configuration."""
        return UserAgentConfig()

    @staticmethod
    def email_from_address() -> str:
        """'From:' email address when sending emails."""
        value = env_value('MC_EMAIL_FROM_ADDRESS', required=False)
        if value is None:
            value = 'info@mediacloud.org'
        return value

    @staticmethod
    def solr_url() -> str:
        """Solr server URL."""
        # "solr-shard-01" container's name from docker-compose.yml
        url = 'http://solr-shard-01:8983/solr'

        # Solr doesn't like extra slashes apparently
        url = re.sub(r'/+$', '', url)

        return url

    @staticmethod
    def extractor_api_url() -> str:
        """URL of the extractor API."""
        # "extract-article-from-page" container's name from docker-compose.yml; will round-robin between servers
        return "http://extract-article-from-page:8080/extract"
