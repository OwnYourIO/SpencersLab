"""immich-hugo-publish — commit the synced content/ batch and drive the ONE
sync PR on Forgejo (chunks/C01.md "immich-hugo-publish — unchanged").

Mechanics pinned by the contract and owner answer 4: `git checkout -B` the
bot-owned branch, stage content/, commit; nothing staged exits `unchanged`
without pushing. The branch is an ephemeral single-commit batch, so the
force-push of THIS bot-owned branch is the documented exemption to the
no-force-push rule — never a human branch. Then create-or-update the PR with
head=<branch> so the farm preview always shows exactly one open sync PR."""

import argparse
import os
import subprocess
import sys
from datetime import date
from pathlib import Path

from . import http_client

DEFAULT_BRANCH = "immich-sync"
DEFAULT_BASE = "main"


class PublishError(Exception):
    """Any loud failure: reported on stderr, non-zero exit, no traceback."""


def _git(site_dir, *args, env_extra=None, check=True):
    env = {**os.environ, **(env_extra or {})}
    proc = subprocess.run(
        ["git", "-C", str(site_dir), *args],
        capture_output=True, text=True, env=env,
    )
    if check and proc.returncode != 0:
        raise PublishError(
            f"git {' '.join(args)} failed ({proc.returncode}): {proc.stderr.strip()[:300]}"
        )
    return proc


def resolve_pr_body(cfg):
    body = cfg["pr_body"] or f"Immich album sync ({date.today().isoformat()})"
    if cfg["summary"]:
        body = f"{body}\n\n{cfg['summary']}"
    return body


def _find_open_pr(pulls, branch):
    for pr in pulls or []:
        if pr.get("state") != "open":
            continue
        head = pr.get("head") or {}
        if branch in (head.get("name"), head.get("ref")):
            return pr
    return None


def publish(cfg):
    site = Path(cfg["site_dir"])
    branch = cfg["branch"]
    _git(site, "checkout", "-B", branch)
    if not (site / "content").is_dir():
        raise PublishError(f"{site / 'content'} is not a directory — nothing to publish")
    # -A with the content/ pathspec ensures ledger deletions (§7) stage on
    # every git version and keeps the stage inside content/ — the HARD
    # GUARDS' "writes only under content/" mirrored on the git side.
    _git(site, "add", "-A", "--", "content/")
    if _git(site, "diff", "--cached", "--quiet", check=False).returncode == 0:
        print("PUBLISH_RESULT unchanged")
        return 0

    identity = {}
    if cfg["identity_name"]:
        identity["GIT_AUTHOR_NAME"] = identity["GIT_COMMITTER_NAME"] = cfg["identity_name"]
    if cfg["identity_email"]:
        identity["GIT_AUTHOR_EMAIL"] = identity["GIT_COMMITTER_EMAIL"] = cfg["identity_email"]
    _git(site, "commit", "-m", cfg["pr_title"], env_extra=identity)
    _git(site, "push", "-f", "origin", branch)

    headers = {"Authorization": f"token {cfg['pat']}"}
    pulls_url = f"{cfg['forgejo_url'].rstrip('/')}/api/v1/repos/{cfg['repo']}/pulls"
    body = resolve_pr_body(cfg)
    existing = _find_open_pr(http_client.json_request("GET", pulls_url, headers=headers), branch)
    if existing:
        pr = http_client.json_request(
            "PATCH", f"{pulls_url}/{existing['index']}", headers=headers, body={"body": body})
    else:
        pr = http_client.json_request(
            "POST", pulls_url, headers=headers,
            body={"title": cfg["pr_title"], "body": body, "head": branch, "base": DEFAULT_BASE})
    print(f"PR_URL={pr['html_url']}")
    return 0


def build_arg_parser():
    parser = argparse.ArgumentParser(prog="immich-hugo-publish")
    for flag, env in (
        ("--site-dir", "SITE_DIR"),
        ("--branch", "BRANCH"),
        ("--forgejo-url", "FORGEJO_URL"),
        ("--forgejo-repo", "FORGEJO_REPO"),
        ("--forgejo-pat", "FORGEJO_PAT"),
        ("--pr-title", "PR_TITLE"),
        ("--pr-body", "PR_BODY"),
        ("--summary", "SUMMARY"),
        ("--git-identity-name", "GIT_IDENTITY_NAME"),
        ("--git-identity-email", "GIT_IDENTITY_EMAIL"),
    ):
        parser.add_argument(flag, dest=env.lower(), default=None)
    return parser


def read_config(argv=None):
    args = build_arg_parser().parse_args(argv)

    def pick(flag_value, env_name, default=None, required=False):
        if flag_value is not None:
            return flag_value
        from_environ = os.environ.get(env_name) or None
        if from_environ is None:
            if required:
                raise PublishError(f"missing required configuration: {env_name} (env or matching --flag)")
            return default
        return from_environ

    return {
        "site_dir": pick(args.site_dir, "SITE_DIR", required=True),
        "branch": pick(args.branch, "BRANCH", default=DEFAULT_BRANCH),
        "forgejo_url": pick(args.forgejo_url, "FORGEJO_URL", required=True),
        "repo": pick(args.forgejo_repo, "FORGEJO_REPO", required=True),
        "pat": pick(args.forgejo_pat, "FORGEJO_PAT", required=True),
        "pr_title": pick(args.pr_title, "PR_TITLE", default="Immich sync"),
        "pr_body": pick(args.pr_body, "PR_BODY"),
        "summary": pick(args.summary, "SUMMARY"),
        "identity_name": pick(args.git_identity_name, "GIT_IDENTITY_NAME"),
        "identity_email": pick(args.git_identity_email, "GIT_IDENTITY_EMAIL"),
    }


def main():
    try:
        return publish(read_config())
    except (PublishError, http_client.HttpError, OSError, ValueError) as exc:
        print(f"immich-hugo-publish: error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
