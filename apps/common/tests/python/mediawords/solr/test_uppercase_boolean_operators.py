# noinspection PyProtectedMember
from mediawords.solr import _uppercase_boolean_operators


def test_uppercase_boolean_operators():
    assert _uppercase_boolean_operators('foo and bar or baz not xyz') == 'foo AND bar OR baz NOT xyz'
    assert _uppercase_boolean_operators(
        ['foo', 'AND', 'bar', 'OR', 'baz', 'NOT', 'xyz']
    ) == ['foo', 'AND', 'bar', 'OR', 'baz', 'NOT', 'xyz']
    assert _uppercase_boolean_operators(
        ['foo', 'AND', 'bar', ['OR', 'baz'], 'NOT', 'xyz']
    ) == ['foo', 'AND', 'bar', ['OR', 'baz'], 'NOT', 'xyz']
