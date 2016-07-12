import os

from mc_solr.constants import MC_DIST_DIR


def resolve_absolute_path(name, must_exist=False):
    """Return absolute path to object (file or directory) under solr-external/."""
    script_path = os.path.dirname(os.path.abspath(__file__))
    dist_path = os.path.join(script_path, "..", name)
    if must_exist:
        if not os.path.isdir(dist_path):
            raise Exception("Object '%s' at path '%s' does not exist." % (name, resolve_absolute_path))
    return os.path.abspath(dist_path)
