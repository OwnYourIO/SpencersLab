# Forgejo git-over-SSH on port 22222 — client migration — 2026-10-23

Both Forgejo instances (dev + infra) now serve git-over-SSH to mesh/LAN
clients on port **22222**, via the k3s traefik Gateway (Gateway API TCPRoute
→ the `<instance>-ssh` ClusterIP Service). The clone URLs shown in the
Forgejo UI change shape accordingly. The node's own sshd stays on :22
(user decision) — see the warning at the bottom.

## New clone URL shape

| Instance | SSH clone URL |
|---|---|
| dev | `ssh://git@git.scifi.farm:22222/<owner>/<repo>.git` |
| infra | `ssh://git@git.spencerslab.com:22222/<owner>/<repo>.git` |

`forgejo.spencerslab.com` is a UI alias of the infra instance — it shows the
same `ssh://git@git.spencerslab.com:22222/…` clone URLs.

Repoint an existing remote:

```sh
git remote set-url origin ssh://git@git.scifi.farm:22222/<owner>/<repo>.git
```

## Keep scp-style URLs with `~/.ssh/config`

If you prefer scp-style remotes (`git@git.scifi.farm:<owner>/<repo>.git`)
that carry no port, map the port per host in `~/.ssh/config`:

```
Host git.scifi.farm
    Port 22222
Host git.spencerslab.com
    Port 22222
```

This also fixes `coder gitssh` in dev workspaces, which forwards ssh args
(including `-p`): with the Host/Port block, the scp-style host it dials
lands on 22222 instead of the node sshd.

## One-time known_hosts prompt

The first ssh to each host connects as `[host]:22222`, so ssh shows a
one-time accept prompt for the new bracketed known_hosts entry. The host
keys themselves are unchanged — they persist on the forgejo data PVCs; only
the entry name gains the port.

## Port 22 on the git hosts is still the node sshd

Port 22 on git.scifi.farm and git.spencerslab.com remains the NODE sshd, not
Forgejo. A plain `git clone git@host:owner/repo.git` without the Port 22222
mapping (or an ssh:// URL that names :22222) lands on the wrong daemon and
fails. Use the ssh:// URL with :22222 or the `~/.ssh/config` block above.
