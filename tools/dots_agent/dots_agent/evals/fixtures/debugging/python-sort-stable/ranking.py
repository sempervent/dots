def rank(rows):
    # unstable / wrong key
    return sorted(rows, key=lambda r: r['score'], reverse=False)
