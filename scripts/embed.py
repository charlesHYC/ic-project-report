#!/usr/bin/env python3
"""Fold a report's stylesheet and images into the HTML, making one file.

A report that references figures/*.png stops working the moment it is mailed,
copied to a phone, or opened from a different directory. Inlining everything
as data: URIs makes the single file the whole deliverable.

    python3 embed.py report.html [-o report_standalone.html]

Rewrites, relative to the HTML's own directory:
  <link rel="stylesheet" href="x.css">  ->  <style> ... </style>
  <img src="figures/x.png">             ->  <img src="data:image/png;base64,...">

Already-inlined data: URIs and remote http(s) references are left alone. A
reference that does not resolve is reported and the run fails, because a
missing figure in a report is worse than no report.
"""
import argparse
import base64
import os
import re
import sys

MIME = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
        '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp'}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('html')
    ap.add_argument('-o', '--out', help='default: <name>_standalone.html')
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args()

    base = os.path.dirname(os.path.abspath(a.html))
    with open(a.html, encoding='utf-8') as f:
        s = f.read()
    missing, imgs, css = [], 0, 0

    def resolve(ref):
        p = os.path.join(base, ref)
        return p if os.path.exists(p) else None

    def do_css(m):
        nonlocal css
        ref = m.group(1)
        if ref.startswith(('data:', 'http:', 'https:', '//')):
            return m.group(0)
        p = resolve(ref)
        if not p:
            missing.append(ref)
            return m.group(0)
        css += 1
        with open(p, encoding='utf-8') as f:
            return '<style>\n' + f.read().rstrip() + '\n</style>'

    def do_img(m):
        nonlocal imgs
        pre, ref, post = m.group(1), m.group(2), m.group(3)
        if ref.startswith(('data:', 'http:', 'https:', '//')):
            return m.group(0)
        p = resolve(ref)
        if not p:
            missing.append(ref)
            return m.group(0)
        mime = MIME.get(os.path.splitext(p)[1].lower())
        if not mime:
            missing.append(ref + ' (unknown image type)')
            return m.group(0)
        with open(p, 'rb') as f:
            b64 = base64.b64encode(f.read()).decode()
        imgs += 1
        return '%sdata:%s;base64,%s%s' % (pre, mime, b64, post)

    s = re.sub(r'<link[^>]+rel=["\']stylesheet["\'][^>]*href=["\']([^"\']+)["\'][^>]*>',
               do_css, s)
    s = re.sub(r'(<img\b[^>]*\bsrc=["\'])([^"\']+)(["\'])', do_img, s)

    if missing:
        print('ERROR: %d reference(s) did not resolve, relative to %s:'
              % (len(missing), base), file=sys.stderr)
        for r in dict.fromkeys(missing):
            print('  ' + r, file=sys.stderr)
        sys.exit(1)

    out = a.out or re.sub(r'\.html?$', '', a.html) + '_standalone.html'
    with open(out, 'w', encoding='utf-8') as f:
        f.write(s)
    if not a.quiet:
        print('%s: %d image(s), %d stylesheet(s), %.1f KB'
              % (out, imgs, css, os.path.getsize(out) / 1024))


if __name__ == '__main__':
    main()
