import socket

from mediawords.util.network import (
    hostname_resolves, fqdn, random_unused_port, tcp_port_is_open, wait_for_tcp_port_to_open,
    wait_for_tcp_port_to_close)


# noinspection SpellCheckingInspection
def test_hostname_resolves():
    assert hostname_resolves('www.mit.edu') is True
    assert hostname_resolves('SHOULDNEVERRESOLVE-JKFSDHFKJSDJFKSD.mil') is False


def test_fqdn():
    fq_hostname = fqdn()
    assert fq_hostname != ''
    assert hostname_resolves(fq_hostname) is True


def test_tcp_port_is_open():
    random_port = random_unused_port()
    assert tcp_port_is_open(random_port) is False

    # Open port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('localhost', random_port))
    s.listen()
    assert tcp_port_is_open(random_port) is True

    # Close port
    s.close()
    assert tcp_port_is_open(random_port) is False


def test_wait_for_tcp_port_to_open():
    random_port = random_unused_port()
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is False

    # Open port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('localhost', random_port))
    s.listen()
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is True

    # Close port
    s.close()
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is False


def test_wait_for_tcp_port_to_close():
    random_port = random_unused_port()
    assert wait_for_tcp_port_to_close(port=random_port, retries=2) is True

    # Open port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('localhost', random_port))
    s.listen()
    assert wait_for_tcp_port_to_close(port=random_port, retries=2) is False

    # Close port
    s.close()
    assert wait_for_tcp_port_to_close(port=random_port, retries=2) is True


def test_random_unused_port():
    random_port = random_unused_port()
    assert tcp_port_is_open(random_port) is False
