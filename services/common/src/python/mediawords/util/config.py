import os

# noinspection PyPackageRequirements
import yaml

from mediawords.util.log import create_logger
from mediawords.util.paths import mc_root_path
from mediawords.util.perl import decode_object_from_bytes_if_needed

try:
    # noinspection PyPackageRequirements
    from yaml import CLoader as Loader
except ImportError:
    # noinspection PyPackageRequirements
    from yaml import Loader

log = create_logger(__name__)

__CONFIG = None


class McConfigException(Exception):
    pass


def get_config() -> dict:
    """Get configuration dictionary."""
    global __CONFIG

    if __CONFIG is not None:
        return __CONFIG

    # FIXME: This should be standardized
    set_config_file(os.path.join(mc_root_path(), "mediawords.yml"))

    # noinspection PyTypeChecker
    # FIXME inspection could still be enabled here
    return __CONFIG


def __parse_yaml(config_file: str) -> dict:
    """Parse and return YAML file with configuration."""
    if not os.path.isfile(config_file):
        raise McConfigException("Configuration file '%s' was not found." % config_file)

    yaml_file = open(config_file, 'r').read()
    yaml_data = yaml.load(yaml_file, Loader=Loader)
    return yaml_data


def set_config_file(config_file: str) -> None:
    """Set the cached configuration dictionary from a file path."""
    if not os.path.isfile(config_file):
        raise McConfigException("Configuration file '%s' was not found." % config_file)

    set_config(__parse_yaml(config_file))


def __merge_configs_internal(a: dict, b: dict, path=None) -> dict:
    """Merges b into a (http://stackoverflow.com/a/7205107/200603)"""
    if path is None:
        path = []
    for key in b:
        if key in a:
            if isinstance(a[key], dict) and isinstance(b[key], dict):
                __merge_configs_internal(a[key], b[key], path + [str(key)])
            elif a[key] == b[key]:
                pass  # same leaf value
            else:
                log.debug(
                    "Overwriting '%(key)s' default value '%(default_value)s' with custom '%(custom_value)s" % {
                        'key': key,
                        'default_value': a[key],
                        'custom_value': b[key]
                    })
                a[key] = b[key]
        else:
            a[key] = b[key]
    return a


def __merge_configs(config: dict, static_defaults: dict) -> dict:
    """Merge configs with precedence for the mediawords.yml config."""

    merged_config = static_defaults.copy()
    merged_config = __merge_configs_internal(merged_config, config)

    return merged_config


def set_config(config: dict) -> None:
    """Set cached configuration dictionary."""
    global __CONFIG

    if __CONFIG is not None:
        log.debug("config object already cached")

    # MC_REWRITE_TO_PYTHON: Catalyst::Test might want to set a couple of values which end up as being "binary"
    config = decode_object_from_bytes_if_needed(config)

    static_defaults = __read_static_defaults()

    __CONFIG = __merge_configs(config, static_defaults)

    __CONFIG = __set_dynamic_defaults(__CONFIG)

    __verify_settings(__CONFIG)


def __read_static_defaults() -> dict:
    """Return configuration defaults dictionary."""
    defaults_file_yml = os.path.join(mc_root_path(), "mediawords.yml.dist")
    static_defaults = __parse_yaml(defaults_file_yml)
    return static_defaults


def __verify_settings(config: dict) -> None:
    """Verify configuration dictionary, print warnings or raise Exceptions if something's not right."""
    if 'database' not in config or config['database'] is None or len(config['database']) < 1:
        raise McConfigException("No database connections configured")

    # Warn if there's a foreign database set for storing raw downloads
    if "raw_downloads" in config["database"]:
        log.warning("""
            You have a foreign database set for storing raw downloads as
            /database/label[raw_downloads].

            Storing raw downloads in a foreign database is no longer supported so please
            remove database connection credentials with label "raw_downloads".
        """)

    # Warn if no job brokers are configured
    if 'job_manager' not in config or config['job_manager'] is None:
        log.warning('Please configure a job manager under "job_manager" root key in mediawords.yml.')
    else:
        if 'rabbitmq' not in config['job_manager'] or config['job_manager']['rabbitmq'] is None:
            log.warning('Please configure "rabbitmq" job manager under "job_manager" root key in mediawords.yml.')


def __set_dynamic_defaults(config: dict) -> dict:
    """Fill configuration dictionary with some preset values."""
    if 'mediawords' not in config or config['mediawords'] is None:
        raise McConfigException('Configuration does not have "mediawords" key')

    if 'data_dir' not in config['mediawords'] or config['mediawords']['data_dir'] is None:
        # FIXME create a helper in 'paths'
        config['mediawords']['data_dir'] = os.path.join(mc_root_path(), 'data')

    # FIXME probably not needed
    if 'session' not in config or config['session'] is None:
        config['session'] = {}
    if 'storage' not in config['session'] or config['session']['storage'] is None:
        config['session']['storage'] = os.path.join(os.path.expanduser('~'), "tmp", "mediacloud-session")

    # MC_REWRITE_TO_PYTHON: probably not needed after Python rewrite
    if 'Plugin::Authentication' not in config or config['Plugin::Authentication'] is None:
        config['Plugin::Authentication'] = {
            "default_realm": 'users',
            "users": {
                "credential": {
                    "class": 'MediaWords'
                },
                "store": {
                    "class": 'MediaWords'
                }
            }
        }

    return config
