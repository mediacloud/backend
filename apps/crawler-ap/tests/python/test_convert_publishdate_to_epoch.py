# noinspection PyProtectedMember
from crawler_ap.ap import _convert_publishdate_to_epoch


def test_convert_publishdate_to_epoch() -> None:
    """Test publishdate time conversion to epoch (from UTC datetime) is correct"""
    assert _convert_publishdate_to_epoch('2019-01-01T12:00:00Z') == 1546344000
