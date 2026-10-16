import json, glob, os, sys
d = os.environ.get("CTX_OUT") or os.path.join(os.environ["TMPDIR"], "focus-context-spike")
price = {"gpt41": (2, 8), "gpt41mini": (0.4, 1.6), "gpt56luna": (0.2, 1.2), "llama33": (0.71, 0.71), "dsv4flash": (0.19, 0.51), "decision-1": (0.042, 0)}
order = {"app": 0, "title": 1, "meta": 2, "full": 3}
rows = []
def resweep(r):
    """Decision-1 also answers a yes/no membership question; sweep that signal on the same calls."""
    rows = []
    for t in [0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.98]:
        rescued, seduced, missed, unstable = 0, [], [], 0
        for c in r["cases"]:
            votes = [float(a["note"].split("=")[1]) >= t for a in c["answers"] if (a.get("note") or "").startswith("noul=")]
            if len(set(votes)) > 1: unstable += 1
            if c["rescue"]:
                if votes and all(votes): rescued += 1
                else: missed.append(c["id"])
            elif any(votes): seduced.append(c["id"])
        rows.append({"threshold": t, "rescued": rescued, "seduced": len(seduced), "unstable": unstable,
                     "recall": rescued / 15, "seducedCases": seduced, "missedCases": missed})
    return rows

reports = []
for f in glob.glob(os.path.join(d, "report-*.json")):
    r = json.load(open(f))
    reports.append(r)
    if r["backend"] == "systemone":
        reports.append(dict(r, model=r["model"] + "/noul", sweep=resweep(r)))
for r in reports:
    clean = [s for s in r["sweep"] if s["seduced"] == 0 and s["unstable"] == 0]
    best = max(clean, key=lambda s: (s["rescued"], -s["threshold"])) if clean else \
        min(r["sweep"], key=lambda s: (s["seduced"], -s["rescued"], s["unstable"]))
    bar = any(s["seduced"] == 0 and s["unstable"] == 0 and s["recall"] >= 0.75 for s in r["sweep"])
    p = price.get(r["model"].split("/")[0])
    cost = f'${880_000 * (r["meanInputTokens"] * p[0] + 2 * p[1]) / 1e6:,.0f}' if p else "$0"
    rows.append((r["backend"], r["model"], r["variant"], order[r["level"]], r["level"], best, bar, r["p50LatencyMs"], r["meanInputTokens"], r["errors"], cost))
rows.sort(key=lambda x: (x[0] != "local", x[1], x[2], x[3]))
print(f'{"judge":28} {"level":6} {"t":>5} {"rescued":>8} {"seduced":>8} {"unstable":>9} bar  {"p50 ms":>7} {"in tok":>7} {"err":>4} {"$/1k users/mo":>14}  seduced cases / missed')
for b, m, v, _, l, s, bar, lat, tok, err, cost in rows:
    name = f"{m}/{v}" if b == "local" else (m if "/" in m else (m + "/choice" if b == "systemone" else m))
    print(f'{name:28} {l:6} {s["threshold"]:>5} {s["rescued"]:>5}/15 {s["seduced"]:>8} {s["unstable"]:>9} {"✓" if bar else " ":3}  {int(lat):>7} {int(tok):>7} {err:>4} {cost:>14}  {",".join(s["seducedCases"])} / {",".join(s["missedCases"])}')
