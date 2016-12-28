from mediawords.util.network import *


# noinspection SpellCheckingInspection
def test_hostname_resolves():
    assert hostname_resolves('www.mit.edu') is True
    assert hostname_resolves('SHOULDNEVERRESOLVE-JKFSDHFKJSDJFKSD.mil') is False


def test_fqdn():
    fq_hostname = fqdn()
    assert fq_hostname != ''
    assert hostname_resolves(fq_hostname) is True


def __random_unused_port():
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('', 0))
    s.listen(1)
    port = s.getsockname()[1]
    s.close()
    return port


def test_tcp_port_is_open():
    random_port = __random_unused_port()
    assert tcp_port_is_open(random_port) is False

    # Open port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('localhost', random_port))
    s.listen(1)
    assert tcp_port_is_open(random_port) is True

    # Close port
    s.close()
    assert tcp_port_is_open(random_port) is False


def test_wait_for_tcp_port_to_open():
    random_port = __random_unused_port()
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is False

    # Open port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('localhost', random_port))
    s.listen(1)
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is True

    # Close port
    s.close()
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is False
