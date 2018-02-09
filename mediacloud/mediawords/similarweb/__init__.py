from mediawords.util.config import get_config as py_get_config
from .similarweb import SimilarWebClient
from .tasks import update  # noqa


def get_similarweb_client():
    config = py_get_config()
    return SimilarWebClient(api_key=config['similarweb']['api_key'])
