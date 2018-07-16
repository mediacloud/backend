import os
from typing import Dict, List, Optional


def postgresql_hostname() -> str:
    return 'mediacloud-postgresql-pgbouncer'


def postgresql_port() -> int:
    return 6432


def postgresql_username() -> str:
    return 'mediacloud'


def postgresql_password() -> str:
    return 'mediacloud'


def postgresql_database() -> str:
    return 'mediacloud'


def rabbitmq_hostname() -> str:
    return 'mediacloud-rabbitmq-server'


def rabbitmq_port() -> int:
    return 5672


def rabbitmq_username() -> str:
    return 'mediacloud'


def rabbitmq_password() -> str:
    return 'mediacloud'


def rabbitmq_vhost() -> str:
    return '/mediacloud'


def rabbitmq_timeout() -> int:
    return 60


def solr_url() -> str:
    return "http://mediacloud-solr-shard:8983/solr"


def http_user_agent() -> str:
    return "mediawords bot (http://cyber.law.harvard.edu)"


def http_owner() -> str:
    return "mediawords@cyber.law.harvard.edu"


def mail_from_address() -> str:
    return "noreply@mediacloud.org"


def mail_smtp_hostname() -> str:
    return 'mediacloud-mail-postfix-server'


def mail_smtp_port() -> int:
    return 25


def read_all_downloads_from_s3() -> bool:
    """Read all non-inline ("content") downloads from S3."""
    return bool(int(os.environ.get('MC_READ_ALL_DOWNLOADS_FROM_S3', False)))


def fallback_postgresql_downloads_to_s3() -> bool:
    """Fallback PostgreSQL downloads to Amazon S3.

    If download doesn't exist in PostgreSQL storage, S3 will be tried instead.
    """
    return bool(int(os.environ.get('MC_FALLBACK_POSTGRESQL_DOWNLOADS_TO_S3', False)))


def cache_s3_downloads() -> bool:
    """Enable local Amazon S3 download caching."""
    return bool(int(os.environ.get('MC_CACHE_S3_DOWNLOADS', False)))


def db_statement_timeout() -> int:
    """Controls the maximum time SQL queries can run for -- time is in ms."""
    return int(os.environ.get('MC_DB_STATEMENT_TIMEOUT', 600000))


def large_work_mem() -> str:
    """Speed up slow queries by setting the PostgreSQL work_mem parameter to this value.

    By default the initial Postgresql value of work_mem is used.
    """
    return os.environ.get('MC_LARGE_WORK_MEM', '3GB')


def ascii_hack_downloads_id() -> Optional[int]:
    """downloads_id under which to strip all non-ASCII characters."""
    return int(os.environ.get('MC_ASCII_HACK_DOWNLOADS_ID', None)) or None


def web_store_num_parallel() -> int:
    """Settings for parallel_get()."""
    return int(os.environ.get('MC_WEB_STORE_NUM_PARALLEL', 10))


def web_store_timeout() -> int:
    """Settings for parallel_get()."""
    return int(os.environ.get('MC_WEB_STORE_PER_DOMAIN_TIMEOUT', 90))


def web_store_per_domain_timeout() -> int:
    """Settings for parallel_get()."""
    return int(os.environ.get('MC_WEB_STORE_PER_DOMAIN_TIMEOUT', 1))


def blacklist_url_pattern() -> Optional[str]:
    """Fail all HTTP requests that match the following pattern.

    Example: "^https?://[^/]*some-website.com"
    """
    return os.environ.get('MC_BLACKLIST_URL_PATTERN', None)


def ignore_schema_version() -> bool:
    """Set to "true" (without quotes) to skip requirement to run on the correct
    database schema version."""
    return bool(int(os.environ.get('MC_IGNORE_SCHEMA_VERSION', False)))


def download_storage_locations() -> List[str]:
    """One or more storage methods to store downloads in.
    
    The path of the last download storage method listed below will be stored in
    "downloads.path" database column.
    """
    env_locations = os.environ.get('MC_DOWNLOAD_STORAGE_LOCATIONS', None)
    if env_locations:
        locations = ';'.split(env_locations)
    else:
        locations = ['postgresql']

    return locations


def s3_downloads_access_key_id() -> Optional[str]:
    """Bucket for storing raw downloads."""
    return os.environ.get('MC_S3_DOWNLOADS_ACCESS_KEY_ID', None)


def s3_downloads_secret_access_key() -> Optional[str]:
    """Bucket for storing raw downloads."""
    return os.environ.get('MC_S3_DOWNLOADS_SECRET_ACCESS_KEY', None)


def s3_downloads_bucket_name() -> Optional[str]:
    """Bucket for storing raw downloads."""
    return os.environ.get('MC_S3_DOWNLOADS_BUCKET_NAME', None)


def s3_downloads_directory_name() -> Optional[str]:
    """Bucket for storing raw downloads."""
    return os.environ.get('MC_S3_DOWNLOADS_DIRECTORY_NAME', None)


def crawler_authenticated_domains() -> List[Dict[str, str]]:
    """Domains that might need HTTP auth credentials to work."""
    domains = []

    env_domains = os.environ.get('MC_CRAWLER_AUTHENTICATED_DOMAINS', None)
    if env_domains:
        for domain in ';'.split(env_domains):
            username_password, domain = '@'.split()
            username, password = ':'.split(username_password)
            domains.append({
                'domain': domain,
                'user': username,
                'password': password,
            })

    return domains
