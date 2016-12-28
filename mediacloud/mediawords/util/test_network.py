from mediawords.util.network import *


# noinspection SpellCheckingInspection
def test_hostname_resolves():
    assert hostname_resolves('www.mit.edu') is True
    assert hostname_resolves('SHOULDNEVERRESOLVE-JKFSDHFKJSDJFKSD.mil') is False


def test_fqdn():
    fq_hostname = fqdn()
    assert fq_hostname != ''
    assert hostname_resolves(fq_hostname) is True
