#!/usr/bin/env python3
"""Publication sur la page Facebook « الإعراب » via l'API Graph.

Le jeton de page est lu dans FB_PAGE_TOKEN, l'identifiant de page dans FB_PAGE_ID.
Le jeton n'est jamais affiché ni écrit. Chaque action d'écriture est consignée
dans docs/facebook/journal.md (sauf --dry-run).

Commandes :
  page                                  infos de la page (lecture)
  post     --message TXT [--link URL]   post texte
  photo    --image PNG --message TXT    post photo
  comment  --post-id ID --message TXT [--image PNG]
  comments --post-id ID                 liste les commentaires (JSON)
  winners  --post-id ID --grid JSON [--max 3]
                                        premiers commentateurs ayant trouvé ≥ 1 mot
Options : --dry-run (n'écrit rien sur Facebook ni dans le journal), --journal CHEMIN.
"""
import argparse
import datetime as dt
import json
import os
import pathlib
import re
import sys
import unicodedata

import requests

API = "https://graph.facebook.com/v26.0"
ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_JOURNAL = ROOT / "docs" / "facebook" / "journal.md"


def token():
    t = os.environ.get("FB_PAGE_TOKEN")
    if not t:
        sys.exit("FB_PAGE_TOKEN absent de l'environnement")
    return t


def page_id():
    p = os.environ.get("FB_PAGE_ID")
    if not p:
        sys.exit("FB_PAGE_ID absent de l'environnement")
    return p


def scrub(text):
    """Retire toute occurrence du jeton d'un texte (messages d'erreur)."""
    t = os.environ.get("FB_PAGE_TOKEN")
    return text.replace(t, "***") if t else text


def call(method, path, *, params=None, data=None, files=None):
    params = dict(params or {})
    params["access_token"] = token()
    r = requests.request(method, f"{API}/{path}", params=params, data=data, files=files, timeout=60)
    try:
        body = r.json()
    except ValueError:
        body = {"raw": r.text[:500]}
    if r.status_code >= 400 or "error" in body:
        err = body.get("error", body)
        sys.exit(scrub(f"Erreur Facebook {r.status_code} : {json.dumps(err, ensure_ascii=False)}"))
    return body


def journal(path, kind, text, fb_id, link=None):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text("# Journal des publications — page الإعراب\n\n", encoding="utf-8")
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    excerpt = " ".join(text.split())[:140]
    line = f"- {now} · **{kind}** · id `{fb_id}`"
    if link:
        line += f" · {link}"
    line += f"\n  « {excerpt} »\n"
    with path.open("a", encoding="utf-8") as f:
        f.write(line)


def permalink(fb_id):
    try:
        return call("GET", fb_id, params={"fields": "permalink_url"}).get("permalink_url")
    except SystemExit:
        return None


# ── Normalisation arabe (mêmes règles que l'app) ─────────────────────────────
_DIACRITICS = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ‌‍]")


def normalize(s):
    s = unicodedata.normalize("NFC", s)
    s = _DIACRITICS.sub("", s)
    s = re.sub("[إأآٱ]", "ا", s)
    s = s.replace("ة", "ه").replace("ى", "ي").replace("ؤ", "و").replace("ئ", "ي")
    return s


def grid_words(grid_path):
    g = json.loads(pathlib.Path(grid_path).read_text(encoding="utf-8"))
    words = set()
    for row in g["cells"]:
        for cell in row:
            if cell.get("type") == "clue":
                for cl in cell.get("clues", []):
                    words.add(cl["solution"])
    return words


def cmd_page(a):
    print(json.dumps(call("GET", page_id(), params={"fields": "id,name,fan_count,followers_count,link"}), ensure_ascii=False, indent=2))


def cmd_post(a):
    data = {"message": a.message}
    if a.link:
        data["link"] = a.link
    if a.dry_run:
        print("[dry-run] post texte :\n" + a.message)
        return
    res = call("POST", f"{page_id()}/feed", data=data)
    fb_id = res["id"]
    link = permalink(fb_id)
    journal(a.journal, "post", a.message, fb_id, link)
    print(json.dumps({"id": fb_id, "permalink_url": link}, ensure_ascii=False))


def cmd_photo(a):
    if a.dry_run:
        print(f"[dry-run] post photo {a.image} :\n" + a.message)
        return
    with open(a.image, "rb") as f:
        res = call("POST", f"{page_id()}/photos", data={"message": a.message, "published": "true"}, files={"source": f})
    fb_id = res.get("post_id") or res["id"]
    link = permalink(fb_id)
    journal(a.journal, "photo", a.message, fb_id, link)
    print(json.dumps({"id": fb_id, "photo_id": res.get("id"), "permalink_url": link}, ensure_ascii=False))


def cmd_comment(a):
    if a.dry_run:
        print(f"[dry-run] commentaire sous {a.post_id} (image : {a.image}) :\n" + a.message)
        return
    files = None
    fh = None
    if a.image:
        fh = open(a.image, "rb")
        files = {"source": fh}
    try:
        res = call("POST", f"{a.post_id}/comments", data={"message": a.message}, files=files)
    finally:
        if fh:
            fh.close()
    fb_id = res["id"]
    journal(a.journal, "commentaire", a.message, fb_id, permalink(a.post_id))
    print(json.dumps({"id": fb_id}, ensure_ascii=False))


def fetch_comments(post_id):
    out = []
    params = {"fields": "id,from{name,id},message,created_time", "order": "chronological", "limit": 100}
    path = f"{post_id}/comments"
    while True:
        res = call("GET", path, params=params)
        out.extend(res.get("data", []))
        nxt = res.get("paging", {}).get("cursors", {}).get("after")
        if not nxt or not res.get("paging", {}).get("next"):
            break
        params["after"] = nxt
    return out


def cmd_comments(a):
    print(json.dumps(fetch_comments(a.post_id), ensure_ascii=False, indent=2))


def cmd_winners(a):
    words = {normalize(w): w for w in grid_words(a.grid)}
    pid = page_id()
    winners, seen = [], set()
    for c in fetch_comments(a.post_id):
        frm = c.get("from") or {}
        if not frm or frm.get("id") == pid or frm["id"] in seen:
            continue
        msg = normalize(c.get("message", ""))
        tokens = set(re.findall(r"[ء-ي]+", msg))
        found = [orig for norm, orig in words.items() if norm in tokens or (len(norm) >= 4 and norm in msg)]
        if found:
            seen.add(frm["id"])
            winners.append({"name": frm.get("name", "؟"), "found": found, "created_time": c["created_time"]})
        if len(winners) >= a.max:
            break
    print(json.dumps(winners, ensure_ascii=False, indent=2))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--journal", default=str(DEFAULT_JOURNAL))
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("page").set_defaults(fn=cmd_page)
    s = sub.add_parser("post"); s.add_argument("--message", required=True); s.add_argument("--link"); s.set_defaults(fn=cmd_post)
    s = sub.add_parser("photo"); s.add_argument("--image", required=True); s.add_argument("--message", required=True); s.set_defaults(fn=cmd_photo)
    s = sub.add_parser("comment"); s.add_argument("--post-id", required=True); s.add_argument("--message", required=True); s.add_argument("--image"); s.set_defaults(fn=cmd_comment)
    s = sub.add_parser("comments"); s.add_argument("--post-id", required=True); s.set_defaults(fn=cmd_comments)
    s = sub.add_parser("winners"); s.add_argument("--post-id", required=True); s.add_argument("--grid", required=True); s.add_argument("--max", type=int, default=3); s.set_defaults(fn=cmd_winners)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
