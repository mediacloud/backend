import os
from configparser import ConfigParser

CONFIG_FILE = "tagging.config"

# the weird format for encoding a tag to set by set_name and tag_name
TAG_BY_STRING_FORMAT = "{}:{}"


def _path_to_config_file():
    return os.path.join(os.path.dirname(__file__), CONFIG_FILE)


def _load_config():
    """We need to read the local config file to tell us where the helpful servers are"""
    settings = ConfigParser()
    settings.read(_path_to_config_file())
    return settings

# load a single static copy of config so we don't hit the disk everytime
config = _load_config()
