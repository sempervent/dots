from solution import parse_kv

def test_parse():
    text = '# c\nA=1\n\nB=two\n'
    assert parse_kv(text) == {'A': '1', 'B': 'two'}
