import socket
from mediawords.util.log import create_logger

l = create_logger(__name__)


def hostname_resolves(hostname: str) -> bool:
    """Return True if hostname resolves to IP."""
    try:
        socket.gethostbyname(hostname)
        return True
    except socket.error:
        return False
