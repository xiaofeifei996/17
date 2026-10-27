import base64, json, os, sys, urllib.request, urllib.error, urllib.parse

TOKEN = os.environ["GITHUB_MCP_TOKEN"]
OWNER = "xiaofeifei996"
REPO = sys.argv[1] if len(sys.argv) > 1 else "GanJi"
ROOT = "/var/minis/workspace/ganji"

def api(method, path, body=None):
    url = "https://api.github.com" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "minis")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")

# 1. create repo (ignore if exists)
st, res = api("POST", "/user/repos", {"name": REPO, "private": False,
                                      "description": "赶集日记 — 广西桂平/平南圩日 App + 负一屏小组件",
                                      "auto_init": False})
print("create repo:", st, res.get("full_name") or res.get("message"))
if st not in (201, 422):
    sys.exit(1)

# 2. push files
skip_dirs = {".git"}
count = 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in skip_dirs]
    for fn in filenames:
        full = os.path.join(dirpath, fn)
        rel = os.path.relpath(full, ROOT)
        if rel.startswith("icon-1024.png") and rel.count("/") == 0:
            continue
        with open(full, "rb") as f:
            content = base64.b64encode(f.read()).decode()
        st, res = api("PUT", f"/repos/{OWNER}/{REPO}/contents/{urllib.parse.quote(rel)}",
                      {"message": f"add {rel}", "content": content})
        ok = st in (200, 201)
        print(f"  {rel}: {st} {'' if ok else res.get('message')}")
        if not ok:
            sys.exit(1)
        count += 1
print("uploaded", count, "files")
