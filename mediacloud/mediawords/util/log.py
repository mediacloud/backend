import logging


def create_logger(name):
    """Create and return 'logging' instance."""
    # noinspection SpellCheckingInspection
    formatter = logging.Formatter(fmt='%(asctime)s - %(levelname)s - %(module)s - %(message)s')

    handler = logging.StreamHandler()
    handler.setFormatter(formatter)

    l = logging.getLogger(name)
    l.setLevel(logging.DEBUG)
    l.addHandler(handler)
    return l
