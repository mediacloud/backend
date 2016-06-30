import os

from mc_solr.constants import MC_DIST_DIR


def distribution_path(dist_directory=MC_DIST_DIR):
    """Return path to dist/ where software distributions should be extracted."""
    script_path = os.path.dirname(os.path.abspath(__file__))
    dist_path = os.path.join(script_path, "..", dist_directory)
    if not os.path.isdir(dist_path):
        raise Exception("Distribution directory '%s' at path '%s' does not exist." % (
            dist_directory,
            distribution_path
        ))
    return dist_path
