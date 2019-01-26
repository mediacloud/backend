from typing import List

from mediawords.util.config import env_value_or_raise


class DatabaseConfig(object):
    """PostgreSQL database configuration."""

    @staticmethod
    def hostname() -> str:
        """Hostname."""
        # Container's name from docker-compose.yml
        return "mc_postgresql_pgbouncer"

    @staticmethod
    def port() -> int:
        """Port."""
        # Container's exposed port from docker-compose.yml
        return 6432

    @staticmethod
    def database_name() -> str:
        """Database name."""
        return "mediacloud"

    @staticmethod
    def username() -> str:
        """Username."""
        return "mediacloud"

    @staticmethod
    def password() -> str:
        """Password."""
        return "mediacloud"


class AmazonS3DownloadsConfig(object):
    """Amazon S3 raw download storage configuration."""

    @staticmethod
    def access_key_id() -> str:
        """Access key ID."""
        return env_value_or_raise('MC_DOWNLOADS_AMAZON_S3_ACCESS_KEY_ID')

    @staticmethod
    def secret_access_key() -> str:
        """Secret access key."""
        return env_value_or_raise('MC_DOWNLOADS_AMAZON_S3_SECRET_ACCESS_KEY')

    @staticmethod
    def bucket_name() -> str:
        """Bucket name."""
        return env_value_or_raise('MC_DOWNLOADS_AMAZON_S3_BUCKET_NAME')

    @staticmethod
    def directory_name() -> str:
        """Directory name (prefix)."""
        return env_value_or_raise('MC_DOWNLOADS_AMAZON_S3_DIRECTORY_NAME', allow_empty_string=True)


class RabbitMQConfig(object):
    """RabbitMQ (Celery broker) client configuration."""

    @staticmethod
    def hostname() -> str:
        """Hostname."""
        # Container's name from docker-compose.yml
        return "mc_rabbitmq_server"

    @staticmethod
    def port() -> int:
        """Port."""
        # Container's exposed port from docker-compose.yml
        return 5672

    @staticmethod
    def username() -> str:
        """Username."""
        return "mediacloud"

    @staticmethod
    def password() -> str:
        """Password."""
        return "mediacloud"

    @staticmethod
    def vhost() -> str:
        """Virtual host."""
        return "/mediacloud"

    @staticmethod
    def timeout() -> int:
        """Timeout."""
        # FIXME possibly hardcode it somewhere
        return 60


class SMTPConfig(object):
    """SMTP configuration."""

    @staticmethod
    def hostname() -> str:
        """Hostname."""
        # Container's name from docker-compose.yml
        return 'mc_mail_postfix_server'

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


class DownloadStorageConfig(object):
    """Download storage configuration."""

    @staticmethod
    def storage_locations() -> List[str]:
        """Download storage locations."""
        env_value = env_value_or_raise('MC_DOWNLOADS_STORAGE_LOCATIONS')
        locations = env_value.split(',')
        locations = [location.strip() for location in locations]
        if len(locations) == 0 and locations[0] == '':
            locations = []
        return locations

    @staticmethod
    def read_all_from_s3() -> bool:
        """Whether or not to read all non-inline downloads from S3."""
        return bool(int(env_value_or_raise('MC_DOWNLOADS_READ_ALL_FROM_S3', allow_empty_string=True)))

    @staticmethod
    def fallback_postgresql_to_s3() -> bool:
        """Whether to fallback PostgreSQL downloads to Amazon S3.

        If the download doesn't exist in PostgreSQL storage, S3 will be tried instead."""
        return bool(int(env_value_or_raise('MC_DOWNLOADS_FALLBACK_POSTGRESQL_TO_S3', allow_empty_string=True)))

    @staticmethod
    def cache_s3() -> bool:
        """Whether to enable local Amazon S3 download cache."""
        return bool(int(env_value_or_raise('MC_DOWNLOADS_CACHE_S3', allow_empty_string=True)))


class ParallelGetConfig(object):
    """parallel_get() configuration."""

    @staticmethod
    def num_parallel() -> int:
        """Parallel connection count."""
        return int(env_value_or_raise('MC_PARALLEL_GET_NUM_PARALLEL'))

    @staticmethod
    def timeout() -> int:
        """Connection timeout, in seconds."""
        return int(env_value_or_raise('MC_PARALLEL_GET_TIMEOUT'))

    @staticmethod
    def per_domain_timeout() -> int:
        """Per-domain timeout, in seconds."""
        return int(env_value_or_raise('MC_PARALLEL_GET_PER_DOMAIN_TIMEOUT'))


class CommonConfig(object):
    """Global configuration (shared by all the containers)."""

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
    def parallel_get() -> ParallelGetConfig:
        """parallel_get() configuration."""
        return ParallelGetConfig()

    @staticmethod
    def email_from_address() -> str:
        """'From:' email address when sending emails."""
        return env_value_or_raise('MC_EMAIL_FROM_ADDRESS')

    @staticmethod
    def solr_url() -> str:
        """Solr server URL, e.g. "http://localhost:8983/solr"."""
        # Container's name from docker-compose.yml; will round-robin between servers
        return 'http://mc_solr_shard:8983/solr'

    @staticmethod
    def throttled_user_agent_domain_timeout() -> int:
        """No idea that that is, no one bothered to document it."""
        return int(env_value_or_raise('MC_THROTTLED_USER_AGENT_DOMAIN_TIMEOUT', allow_empty_string=True))
