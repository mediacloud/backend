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


class McFQDNException(Exception):
    pass


def fqdn() -> str:
    """Return Fully Qualified Domain Name (hostname -f), e.g. mcquery2.media.mit.edu."""
    # socket.getfqdn() returns goofy results
    hostname = socket.getaddrinfo(socket.gethostname(), 0, flags=socket.AI_CANONNAME)[0][3]
    if hostname is None or len(hostname) == 0:
        raise McFQDNException("Unable to determine FQDN.")
    hostname = hostname.lower()
    if hostname == 'localhost':
        l.warning("FQDN is 'localhost', are you sure that /etc/hosts is set up properly?")
    if not hostname_resolves(hostname):
        raise McFQDNException("Hostname '%s' does not resolve." % hostname)
    return hostname
