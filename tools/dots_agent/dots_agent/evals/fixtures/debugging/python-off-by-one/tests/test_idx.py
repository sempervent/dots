from solution import last_index

def test_last():
    assert last_index(['a', 'b', 'c']) == 2
    assert last_index([1]) == 0
