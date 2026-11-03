from ranking import rank

def test_rank():
    rows = [{'name':'a','score':2},{'name':'b','score':5},{'name':'c','score':5}]
    out = rank(rows)
    assert out[0]['name'] == 'b'
    assert out[0]['score'] == 5
