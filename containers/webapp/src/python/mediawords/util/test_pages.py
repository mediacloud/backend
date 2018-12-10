from mediawords.util.pages import Pages


def test_pages():
    # Basic test
    pages = Pages(total_entries=50, entries_per_page=10, current_page=5)
    assert pages.previous_page() == 4
    assert pages.next_page() is None
    assert pages.first() == 41
    assert pages.last() == 50
