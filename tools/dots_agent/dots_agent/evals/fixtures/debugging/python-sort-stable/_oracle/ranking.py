def rank(rows):
    return sorted(rows, key=lambda r: (-r['score'], r['name']))
