import socket
import time

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

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

    # Solr (ZooKeeper?) somehow manages to translate underscore to something else, so something like:
    #
    #     ec2_solr_mcquery2
    #
    # becomes:
    #
    #     ec2/solr_mcquery2:7981/solr
    #
    # Can't explain that.
    if '_' in hostname:
        raise McFQDNException("FQDN contains underscore ('_') which might mess up Solr shard naming")

    if not hostname_resolves(hostname):
        raise McFQDNException("Hostname '%s' does not resolve." % hostname)
    return hostname


def tcp_port_is_open(port: int, hostname: str = 'localhost') -> bool:
    """Test if TCP port is open."""

    hostname = decode_object_from_bytes_if_needed(hostname)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex((hostname, port))
    return result == 0


def wait_for_tcp_port_to_open(port: int, hostname: str = 'localhost', retries: int = 60, delay: int = 1) -> bool:
    """Try connecting to TCP port until it opens (or not); return True if managed to connect."""

    hostname = decode_object_from_bytes_if_needed(hostname)

    port_is_open = False
    for retry in range(retries):
        if retry == 0:
            l.info("Trying to connect to %s:%d" % (hostname, port))
        else:
            l.info("Trying to connect to %s:%d, retry %d" % (hostname, port, retry))

        if tcp_port_is_open(port, hostname):
            port_is_open = True
            break
        else:
            time.sleep(delay)
    return port_is_open


def random_unused_port() -> int:
    """Return random unused TCP port that could be used e.g. for testing."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('', 0))
    s.listen(1)
    port = s.getsockname()[1]
    s.close()
    return port
