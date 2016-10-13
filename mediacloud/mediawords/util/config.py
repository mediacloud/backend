import os

# noinspection PyPackageRequirements
import yaml

from mediawords.util.paths import mc_root_path
from mediawords.util.perl import decode_dictionary_from_bytes_if_needed

try:
    # noinspection PyPackageRequirements
    from yaml import CLoader as Loader
except ImportError:
    # noinspection PyPackageRequirements
    from yaml import Loader

from mediawords.util.log import create_logger

l = create_logger(__name__)

__MC_ROOT_DIR = mc_root_path()
__base_dir = __MC_ROOT_DIR  # FIXME remove
__CONFIG = None


def get_mc_root_dir():
    return __MC_ROOT_DIR


def get_config():
    global __CONFIG

    if __CONFIG is not None:
        return __CONFIG

    # TODO: This should be standardized
    set_config_file(os.path.join(__base_dir, "mediawords.yml"))

    return __CONFIG


def __parse_config_file(config_file):
    if not os.path.isfile(config_file):
        raise Exception("Configuration file '%s' was not found." % config_file)

    yaml_file = open(config_file, 'r').read()
    yaml_data = yaml.load(yaml_file, Loader=Loader)
    return yaml_data


def set_config_file(config_file):
    """set the cached config object given a file path"""
    if not os.path.isfile(config_file):
        raise Exception("Configuration file '%s' was not found." % config_file)

    set_config(__parse_config_file(config_file))


def __merge_configs(config, static_defaults):
    """merge configs using Hash::Merge, with precedence for the mediawords.yml config."""

    def __merge_configs_internal(a, b, path=None):
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
                    l.debug(
                        "Overwriting '%(key)s' default value '%(default_value)s' with custom '%(custom_value)s" % {
                            'key': key,
                            'default_value': a[key],
                            'custom_value': b[key]
                        })
                    a[key] = b[key]
            else:
                a[key] = b[key]
        return a

    merged_config = static_defaults.copy()
    merged_config = __merge_configs_internal(merged_config, config)

    return merged_config


def set_config(config):
    global __CONFIG

    if __CONFIG is not None:
        l.warn("config object already cached")

    # FIXME MC_REWRITE_TO_PYTHON: Catalyst::Test might want to set a couple of values which end up as being "binary"
    config = decode_dictionary_from_bytes_if_needed(config)

    static_defaults = __read_static_defaults()

    __CONFIG = __merge_configs(config, static_defaults)

    __set_dynamic_defaults(__CONFIG)

    verify_settings(__CONFIG)


def __read_static_defaults():
    defaults_file_yml = os.path.join(get_mc_root_dir(), "config", "defaults.yml")
    static_defaults = __parse_config_file(defaults_file_yml)
    return static_defaults


def verify_settings(config):
    if 'database' not in config:
        raise Exception("No database connections configured")

    # Warn if there's a foreign database set for storing raw downloads
    if "raw_downloads" in config["database"]:
        l.warn("""
            You have a foreign database set for storing raw downloads as
            /database/label[raw_downloads].

            Storing raw downloads in a foreign database is no longer supported so please
            remove database connection credentials with label "raw_downloads".
        """)

    # Warn if no job brokers are configured
    if 'job_manager' not in config:
        l.warn('Please configure a job manager under "job_manager" root key in mediawords.yml.')
    else:
        if 'rabbitmq' not in config['job_manager']:
            l.warn('Please configure "rabbitmq" job manager under "job_manager" root key in mediawords.yml.')


def __set_dynamic_defaults(config):
    global __base_dir

    if 'mediawords' not in config:
        raise Exception('Configuration does not have "mediawords" key')

    if 'script_dir' not in config['mediawords']:
        # FIXME use mc_script_dir()
        config['mediawords']['script_dir'] = os.path.join(__base_dir, 'script')
    if 'data_dir' not in config['mediawords']:
        # FIXME create a helper in 'paths'
        config['mediawords']['data_dir'] = os.path.join(__base_dir, 'data')

    # FIXME probably not needed
    if 'session' not in config:
        config['session'] = {}
    if 'storage' not in config['session']:
        config['session']['storage'] = os.path.join(os.path.expanduser('~'), "tmp", "mediacloud-session")

    # FIXME probably not needed after Python rewrite
    if "Plugin::Authentication" not in config:
        config['Plugin::Authentication'] = {
            "default_realm": 'users',
            "users": {
                "credential": {
                    "class": 'Password',
                    "password_field": 'password',
                    "password_type": 'salted_hash',
                    "password_hash_type": 'SHA-256',
                    "password_salt_len": 64,
                },
                "store": {
                    "class": 'MediaWords'
                }
            }
        }

    return config
