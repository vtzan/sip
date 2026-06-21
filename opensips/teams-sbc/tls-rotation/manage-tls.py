#!/usr/bin/env python3
"""
manage-tls.py -- database TLS certificate management & automatic rotation for the
OpenSIPS Microsoft Teams SBC.

All TLS material lives in the `tls_mgm` database table (BLOB columns). This tool:

  check                 report the expiry of every certificate in the table
  set-ca   --ca FILE    install the peer-verification CA bundle (all rows or one)
  load     --domain ID  --cert FILE --key FILE   install a cert/key into one row
  rotate   [--force]    renew every cert that expires within the threshold, via an
                        ACME hook, write it back to the DB and hot-reload OpenSIPS

After any change it runs:   opensips-cli -x mi tls_mgm:reload
so OpenSIPS picks up new certificates with no restart and no dropped calls.

Dependencies:  pip install -r requirements.txt   (PyMySQL, cryptography)
"""
import argparse
import configparser
import datetime
import os
import subprocess
import sys

try:
    import pymysql
except ImportError:
    sys.exit("error: PyMySQL is required (pip install -r requirements.txt)")
try:
    from cryptography import x509
except ImportError:
    sys.exit("error: cryptography is required (pip install -r requirements.txt)")


def load_config(path):
    cfg = configparser.ConfigParser()
    if not cfg.read(path):
        sys.exit(f"error: cannot read config {path}")
    return cfg


def db_connect(cfg):
    # Environment variables (set by the containers) override the config file.
    db = cfg["db"]
    return pymysql.connect(
        host=os.environ.get("DB_HOST", db.get("host", "127.0.0.1")),
        port=int(os.environ.get("DB_PORT", db.getint("port", 3306))),
        user=os.environ.get("DB_USER", db.get("user", "opensips")),
        password=os.environ.get("DB_PASS", db.get("password", "")),
        database=os.environ.get("DB_NAME", db.get("name", "opensips")),
        autocommit=False,
    )


def table(cfg):
    return cfg["db"].get("table", "tls_mgm")


def cert_not_after(pem):
    """Return the leaf certificate's notAfter as a timezone-aware UTC datetime."""
    if not pem:
        return None
    if isinstance(pem, str):
        pem = pem.encode()
    cert = x509.load_pem_x509_certificate(pem)
    try:
        return cert.not_valid_after_utc            # cryptography >= 42
    except AttributeError:
        return cert.not_valid_after.replace(tzinfo=datetime.timezone.utc)


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def mi_call(cfg, method):
    """Invoke an OpenSIPS MI method via HTTP JSON-RPC (mi_url) or opensips-cli."""
    mi_url = os.environ.get("MI_URL", cfg["rotation"].get("mi_url", "")).strip()
    if mi_url:
        import json
        import urllib.request
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method}).encode()
        req = urllib.request.Request(mi_url, data=body,
                                     headers={"Content-Type": "application/json"})
        print(f"  MI {method} -> {mi_url}")
        try:
            urllib.request.urlopen(req, timeout=5).read()
            return True
        except Exception as e:  # noqa: BLE001
            print(f"  warning: MI call failed: {e}", file=sys.stderr)
            return False
    cli = cfg["rotation"].get("opensips_cli", "opensips-cli")
    cmd = cli.split() + ["-x", "mi", method]
    print(f"  reloading: {' '.join(cmd)}")
    rc = subprocess.run(cmd).returncode
    if rc != 0:
        print(f"  warning: '{method}' exited {rc} (is OpenSIPS running yet?)", file=sys.stderr)
    return rc == 0


def reload_opensips(cfg):
    return mi_call(cfg, "tls_mgm:reload")


def sans_for(cfg, domain_id, match_sip_domain):
    """Determine the SAN list to request for a tls_mgm row."""
    if cfg.has_option("map", domain_id):
        return [s.strip() for s in cfg.get("map", domain_id).split(",") if s.strip()]
    if match_sip_domain:
        return [match_sip_domain.strip()]
    return []


# --------------------------------------------------------------------------- #
#  subcommands
# --------------------------------------------------------------------------- #
def cmd_check(cfg, args):
    conn = db_connect(cfg)
    threshold = cfg["rotation"].getint("renew_threshold_days", 30)
    rows = []
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT id, domain, type, match_sip_domain, certificate FROM {table(cfg)} ORDER BY domain"
        )
        rows = cur.fetchall()
    conn.close()
    print(f"{'id':>3}  {'domain':<16} {'type':<6} {'expires (UTC)':<20} {'days':>5}  status")
    for (rid, dom, typ, sni, cert) in rows:
        typ_s = {0: "both", 1: "client", 2: "server"}.get(typ, str(typ))
        na = cert_not_after(cert)
        if na is None:
            print(f"{rid:>3}  {dom:<16} {typ_s:<6} {'<none>':<20} {'-':>5}  NO CERT")
            continue
        days = (na - now_utc()).days
        status = "OK" if days > threshold else ("EXPIRED" if days < 0 else "RENEW")
        print(f"{rid:>3}  {dom:<16} {typ_s:<6} {na:%Y-%m-%d %H:%M}     {days:>5}  {status}")
    return 0


def _update_blob(conn, cfg, domain_id, **cols):
    sets = ", ".join(f"{c} = %s" for c in cols)
    params = list(cols.values()) + [domain_id]
    with conn.cursor() as cur:
        cur.execute(f"UPDATE {table(cfg)} SET {sets} WHERE domain = %s", params)
        return cur.rowcount


def cmd_set_ca(cfg, args):
    ca = open(args.ca, "rb").read()
    conn = db_connect(cfg)
    with conn.cursor() as cur:
        if args.domain:
            cur.execute(f"UPDATE {table(cfg)} SET ca_list = %s WHERE domain = %s", (ca, args.domain))
        else:
            cur.execute(f"UPDATE {table(cfg)} SET ca_list = %s", (ca,))
        n = cur.rowcount
    conn.commit()
    conn.close()
    print(f"updated ca_list on {n} row(s)")
    reload_opensips(cfg)
    return 0


def cmd_load(cfg, args):
    cert = open(args.cert, "rb").read()
    key = open(args.key, "rb").read()
    conn = db_connect(cfg)
    n = _update_blob(conn, cfg, args.domain, certificate=cert, private_key=key)
    conn.commit()
    conn.close()
    if n == 0:
        sys.exit(f"error: no tls_mgm row with domain='{args.domain}'")
    na = cert_not_after(cert)
    print(f"loaded cert into '{args.domain}' (expires {na:%Y-%m-%d})")
    reload_opensips(cfg)
    return 0


def run_acme(cfg, sans):
    """Call the ACME hook; expect CERT=/KEY= lines on stdout. Returns (cert, key)."""
    hook = cfg["acme"].get("hook")
    if not hook:
        sys.exit("error: [acme] hook not configured")
    primary = sans[0]
    cmd = hook.split() + [primary, ",".join(sans)]
    print(f"  issuing via: {' '.join(cmd)}")
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        print(out.stdout, out.stderr, file=sys.stderr)
        raise RuntimeError(f"ACME hook failed ({out.returncode}) for {primary}")
    paths = {}
    for line in out.stdout.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            paths[k.strip()] = v.strip()
    if "CERT" not in paths or "KEY" not in paths:
        raise RuntimeError(f"ACME hook did not print CERT=/KEY= for {primary}")
    return open(paths["CERT"], "rb").read(), open(paths["KEY"], "rb").read()


def cmd_rotate(cfg, args):
    threshold = cfg["rotation"].getint("renew_threshold_days", 30)
    conn = db_connect(cfg)
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT id, domain, type, match_sip_domain, certificate FROM {table(cfg)} ORDER BY domain"
        )
        rows = cur.fetchall()

    changed = 0
    for (rid, dom, typ, sni, cert) in rows:
        sans = sans_for(cfg, dom, sni)
        if not sans:
            print(f"- {dom}: no SAN mapping, skipping")
            continue
        na = cert_not_after(cert)
        days = None if na is None else (na - now_utc()).days
        due = args.force or na is None or days <= threshold
        if not due:
            print(f"- {dom}: ok ({days} days left)")
            continue
        reason = "forced" if args.force else ("no cert" if na is None else f"{days} days left")
        print(f"* {dom}: renewing ({reason}) for {', '.join(sans)}")
        if args.dry_run:
            continue
        try:
            new_cert, new_key = run_acme(cfg, sans)
        except Exception as e:  # noqa: BLE001
            print(f"  ERROR: {e}", file=sys.stderr)
            continue
        _update_blob(conn, cfg, dom, certificate=new_cert, private_key=new_key)
        conn.commit()
        changed += 1
        print(f"  stored new cert (expires {cert_not_after(new_cert):%Y-%m-%d})")

    conn.close()
    if changed and not args.dry_run:
        reload_opensips(cfg)
    print(f"done: {changed} certificate(s) rotated")
    return 0


def main():
    p = argparse.ArgumentParser(description="Database TLS management for the OpenSIPS Teams SBC")
    here = os.path.dirname(os.path.abspath(__file__))
    p.add_argument("--config", default=os.path.join(here, "rotation.conf"))
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("check")

    sp = sub.add_parser("set-ca")
    sp.add_argument("--ca", required=True)
    sp.add_argument("--domain", help="limit to one tls_mgm.domain id (default: all rows)")

    sp = sub.add_parser("load")
    sp.add_argument("--domain", required=True)
    sp.add_argument("--cert", required=True)
    sp.add_argument("--key", required=True)

    sp = sub.add_parser("rotate")
    sp.add_argument("--force", action="store_true", help="renew regardless of expiry")
    sp.add_argument("--dry-run", action="store_true", help="report only, do not issue/write")

    args = p.parse_args()
    cfg = load_config(args.config)
    return {
        "check": cmd_check,
        "set-ca": cmd_set_ca,
        "load": cmd_load,
        "rotate": cmd_rotate,
    }[args.cmd](cfg, args)


if __name__ == "__main__":
    sys.exit(main())
