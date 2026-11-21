# cf-145 C02 — filing the radiance engine dashboard into a NEW `inference:`
# Grafana provider folder (chunks/C02.md; AC1-AC3). Owner ruling OQ-4: the
# dashboard ships as a `grafana.dashboards.inference.radiance` url entry
# pinned to the engine TAG (v1.17.0), served by a provider block that must be
# NAME-COUPLED to the map key — the grafana 10.1.0 chart's
# download_dashboards.sh writes each url entry to the options.path of the
# provider whose `name` EQUALS the `dashboards` map KEY (plan R8, grounded
# from charts/_config.tpl + a live subtree render at plan-approval). A missing
# provider = the JSON downloads NOWHERE, so T4 renders the chart, not just the
# YAML. The cf-105 vllm pair stays byte-untouched under `default:` (parent D6)
# — T5 pins it rather than trusting silence.
#
# Red state at handoff (designed): T1/T2/T3/T4 RED until C02-dev lands the two
# coupled insertions in services/monitoring/prod/values.yaml; T5 legs are
# preserve pins — green today, must stay green. Loud skip ONLY on a missing
# helm binary (helm_ready law); a failed chart pull is a RED naming the
# environment, never a silent pass.
#
# Run per-directory: PATH=$HOME/.local/bin:$PATH python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import functools
import re
import subprocess
import tempfile
from pathlib import Path

import pytest
import yaml

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)

MONITORING_VALUES = R.REPO_ROOT / "services" / "monitoring" / "prod" / "values.yaml"

PROVIDER_NAME = "inference"
PROVIDER_FOLDER = "Inference"          # key -> Title-case display convention (data->Data)
PROVIDER_PATH = "/var/lib/grafana/dashboards/inference"
ENTRY_KEY = "radiance"                 # key == the dashboard JSON's uid
URL_BASE = "https://codeberg.org/StillDeadcode/radiance/raw/tag/"
URL_SUFFIX = "/deploy/grafana/radiance.json"

# Pinned verbatim off today's tree (values.yaml:659-668) — parent D6 law: the
# vllm pair's bytes are C02's forbidden surface; the render half of T5 re-checks
# them post-grafana-subtree.
VLLM_PERF_URL = ("https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/"
                 "examples/observability/dashboards/grafana/performance_statistics.json")
VLLM_QUERY_URL = ("https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/"
                  "examples/observability/dashboards/grafana/query_statistics.json")


def _monitoring_values() -> dict:
    assert MONITORING_VALUES.is_file(), f"cf-145 C02: {MONITORING_VALUES} missing — the filing host vanished"
    return yaml.safe_load(MONITORING_VALUES.read_text())


def _providers() -> list:
    g = _monitoring_values().get("grafana") or {}
    dp = (g.get("dashboardProviders") or {}).get("dashboardproviders.yaml") or {}
    return dp.get("providers") or []


def _dashboards() -> dict:
    g = _monitoring_values().get("grafana") or {}
    return g.get("dashboards") or {}


# --- T1 (AC1): the provider block, R8-coupled ----------------------------------


def test_t1_inference_provider_block_landed():
    """Provider shape per the task block: name/folder/type/options.path — the
    path SUFFIX must equal the name (the R8 name==key==path coupling starts
    here; the map-key half is T2, the render half is T4)."""
    prov = [p for p in _providers() if p.get("name") == PROVIDER_NAME]
    assert prov, (
        f"cf-145 C02 AC1: no provider named {PROVIDER_NAME!r} in grafana.dashboardProviders "
        f"(have: {[p.get('name') for p in _providers()]}) — designed-red until the provider block "
        "lands (without it the radiance.json downloads NOWHERE, plan R8)"
    )
    assert len(prov) == 1, f"cf-145 C02: duplicate {PROVIDER_NAME} provider blocks: {prov}"
    p = prov[0]
    assert p.get("folder") == PROVIDER_FOLDER, (
        f"cf-145 C02 AC1: provider folder {p.get('folder')!r}, want {PROVIDER_FOLDER!r} (key->Title-case display convention)"
    )
    assert p.get("type") == "file", f"cf-145 C02 AC1: provider type {p.get('type')!r}, want file"
    assert (p.get("options") or {}).get("path") == PROVIDER_PATH, (
        f"cf-145 C02 AC1 (R8 coupling): options.path is {(p.get('options') or {}).get('path')!r}, "
        f"want {PROVIDER_PATH} — the write dir the download script resolves by provider name"
    )


# --- T2 (AC1): the dashboards-map entry, keys exactly {url, datasource} --------


def test_t2_inference_radiance_entry_shape():
    """Entry shape verbatim off the vllm precedent (cf-105): key == dashboard
    uid, exactly the two keys, string datasource (the sed-rewrite trigger the
    vllm pair relies on)."""
    dashboards = _dashboards()
    assert PROVIDER_NAME in dashboards, (
        f"cf-145 C02 AC1: grafana.dashboards has no {PROVIDER_NAME!r} key (have: {sorted(dashboards)}) — "
        "the provider half alone files nothing: download_dashboards.sh matches provider NAME to this KEY (R8)"
    )
    entry = (dashboards[PROVIDER_NAME] or {}).get(ENTRY_KEY)
    assert isinstance(entry, dict), (
        f"cf-145 C02 AC1: no {PROVIDER_NAME}.{ENTRY_KEY} entry — designed-red until C02-dev lands it "
        f"(sibling keys under {PROVIDER_NAME}: {sorted(dashboards[PROVIDER_NAME] or {})})"
    )
    assert set(entry) == {"url", "datasource"}, (
        f"cf-145 C02 AC1: entry keys are {sorted(entry)}, want exactly [datasource, url] — "
        "a gnetId/local/json key is a different mechanism than the owner-ruled url entry"
    )
    assert entry["datasource"] == "Prometheus", (
        f"cf-145 C02 AC1: datasource {entry['datasource']!r}, want the STRING Prometheus "
        "(string form triggers the script's sed rewrite of every panel datasource field)"
    )
    url = entry["url"]
    assert url.startswith(URL_BASE) and url.endswith(URL_SUFFIX), (
        f"cf-145 C02 AC1: url {url!r} is not the Codeberg raw-tag path {URL_BASE}<tag>{URL_SUFFIX}"
    )
    # R8 at parse level: every dashboards key needs the same-named provider.
    names = {p.get("name") for p in _providers()}
    missing = [k for k in dashboards if k not in names]
    assert not missing, (
        f"cf-145 C02 AC1 (R8 coupling): dashboards key(s) {missing} have no same-named provider — "
        "their JSONs download nowhere"
    )


# --- T3 (AC2): tag coupling DERIVED from the image-pin authority ---------------


def test_t3_url_tag_coupled_to_image_pin():
    """One authority law (G6): the URL tag is not re-typed — it must equal
    "v" + radiance_testlib.IMAGE_TAG, so bumping the image pin without the
    dashboard URL (or vice versa) goes RED here."""
    entry = (_dashboards().get(PROVIDER_NAME) or {}).get(ENTRY_KEY) or {}
    url = entry.get("url", "")
    m = re.search(re.escape(URL_BASE) + r"(v[^/]+)" + re.escape(URL_SUFFIX), url)
    assert m, (
        f"cf-145 C02 AC2: cannot read a tag segment out of {url!r} — the url-entry half is "
        "not landed or not tag-shaped (red names the C02 edit)"
    )
    assert m.group(1) == f"v{R.IMAGE_TAG}", (
        f"cf-145 C02 AC2: dashboard url tag {m.group(1)!r} != v+IMAGE_TAG {R.IMAGE_TAG!r} from "
        "radiance_testlib — the tag-coupling law (ship the dashboard of the SAME release the "
        "image pin holds); bump both in one commit"
    )


# --- T4 (AC3): the grafana-chart render proof (extract-and-render idiom) -------


def _split_curl_blocks(script: str) -> list[str]:
    """Each url/gnet fetch is one `curl -skf \\` block ending at its
    `> "path"` redirect line; block-scoped checks keep the radiance assertions
    from passing off another entry's lines."""
    out, cur = [], None
    for ln in script.splitlines():
        if ln.startswith("curl -skf"):
            if cur is not None:
                out.append("\n".join(cur))
            cur = [ln]
        elif cur is not None:
            cur.append(ln)
            if ln.startswith("> "):
                out.append("\n".join(cur))
                cur = None
    if cur is not None:
        out.append("\n".join(cur))
    return out


@functools.lru_cache(maxsize=1)
def _grafana_render() -> dict:
    """The plan Commands grafana render leg: extract the top-level `grafana:`
    subtree of the monitoring values, pull the chart at the version READ from
    the same file's charts.grafana.version (one authority; currently 10.1.0),
    template it. Returns the monitoring-grafana ConfigMap's data dict
    (dashboardproviders.yaml + download_dashboards.sh live there)."""
    vals = _monitoring_values()
    sub = vals.get("grafana")
    assert isinstance(sub, dict), "cf-145 C02 AC3: services/monitoring/prod/values.yaml has no grafana: subtree"
    version = ((vals.get("charts") or {}).get("grafana") or {}).get("version")
    repo = ((vals.get("charts") or {}).get("grafana") or {}).get("repository")
    assert version and repo, (
        "cf-145 C02 AC3: charts.grafana.{version,repository} missing from the same values file — "
        "the render leg reads its chart pin from that one authority (currently 10.1.0 / grafana.github.io)"
    )
    with tempfile.TemporaryDirectory(prefix="cf145-grafana-") as tmp:
        t = Path(tmp)
        subtree = t / "grafana-subtree.yaml"
        with subtree.open("w") as fh:
            yaml.safe_dump(sub, fh)
        pull = subprocess.run(
            ["helm", "pull", "grafana", "--repo", repo, "--version", str(version),
             "--untar", "--untardir", str(t)],
            capture_output=True, text=True, timeout=300,
        )
        if pull.returncode != 0:
            # Loud RED naming the environment — a pull failure is never a skip
            # (chunk T4 law; only the helm binary absence skips, loudly).
            raise AssertionError(
                f"cf-145 C02 AC3 (environment): `helm pull grafana --repo {repo} --version {version}` "
                f"failed — chart pulls need cluster-network egress (radiance CI has it via dependency "
                f"update); stderr: {pull.stderr[:500]}"
            )
        chart_dir = t / "grafana"
        assert chart_dir.is_dir(), f"cf-145 C02: helm pull --untar produced no {chart_dir}"
        tmpl = subprocess.run(
            ["helm", "template", "monitoring-grafana", str(chart_dir), "-n", "default", "-f", str(subtree)],
            capture_output=True, text=True, timeout=300,
        )
        if tmpl.returncode != 0:
            raise AssertionError(f"cf-145 C02 AC3: helm template of the grafana subtree failed:\n{tmpl.stderr[:800]}")
        docs = [d for d in yaml.safe_load_all(tmpl.stdout) if d]
        cms = [d for d in docs if d.get("kind") == "ConfigMap" and d["metadata"]["name"] == "monitoring-grafana"]
        assert cms, (
            f"cf-145 C02 AC3: rendered docs carry no monitoring-grafana ConfigMap "
            f"(CMs: {[d['metadata']['name'] for d in docs if d.get('kind') == 'ConfigMap']})"
        )
        return dict(cms[0].get("data") or {})


@helm_skip
def test_t4_rendered_provisioning_carries_inference_provider():
    """The chart renders dashboardProviders VERBATIM (no auto-provider magic):
    the provider half of the edit must reach the provisioning file the pod
    actually reads, name+path intact (R8)."""
    data = _grafana_render()
    raw = data.get("dashboardproviders.yaml")
    assert raw, "cf-145 C02 AC3: rendered monitoring-grafana CM has no dashboardproviders.yaml key"
    provs = ((yaml.safe_load(raw) or {}).get("providers")) or []
    match = [p for p in provs if p.get("name") == PROVIDER_NAME]
    assert match, (
        f"cf-145 C02 AC1/AC3: rendered dashboardproviders.yaml carries no {PROVIDER_NAME} provider "
        f"(names: {[p.get('name') for p in provs]}) — designed-red until the provider block lands"
    )
    assert (match[0].get("options") or {}).get("path") == PROVIDER_PATH, (
        f"cf-145 C02 AC3: rendered provider options.path {(match[0].get('options') or {}).get('path')!r} "
        f"!= {PROVIDER_PATH} — the name==key==path coupling (R8) is what files the JSON into the folder"
    )


@helm_skip
def test_t4_rendered_script_files_radiance_into_inference():
    """The filing proof at template level: the generated script mkdirs the
    provider path, curls the pinned tag url, sed-rewrites the datasource, and
    writes to <provider path>/radiance.json — each checked inside radiance's
    own curl block so a sibling entry cannot stand in (block shape verified
    against the live grafana 10.1.0 render at plan-approval)."""
    data = _grafana_render()
    script = data.get("download_dashboards.sh")
    assert script, "cf-145 C02 AC3: rendered CM has no download_dashboards.sh key"
    assert f"mkdir -p {PROVIDER_PATH}" in script.splitlines(), (
        f"cf-145 C02 AC3: no `mkdir -p {PROVIDER_PATH}` line — the script mkdirs one line per "
        "provider path, so its absence means the provider block never rendered"
    )
    entry = (_dashboards().get(PROVIDER_NAME) or {}).get(ENTRY_KEY) or {}
    url = entry.get("url", "")
    blocks = [b for b in _split_curl_blocks(script) if url and url in b]
    assert blocks, (
        f"cf-145 C02 AC3: no curl block in download_dashboards.sh carries the radiance url {url!r} — "
        "designed-red until the dashboards-map entry lands (the script is GENERATED from that map)"
    )
    block = blocks[0]
    assert f'> "{PROVIDER_PATH}/{ENTRY_KEY}.json"' in block, (
        f"cf-145 C02 AC3 (R8): radiance's curl block does not write to "
        f'"> {PROVIDER_PATH}/{ENTRY_KEY}.json" — the write dir resolves via provider-name==key; '
        "a default/-path write here means the two halves are name-decoupled"
    )
    assert 's/"datasource":.*,/"datasource": "Prometheus",/g' in block, (
        "cf-145 C02 AC3: radiance's block lacks the string-datasource sed rewrite "
        "(the same transform the vllm pair relies on)"
    )


# --- T5 (AC3): the vllm pair, pinned not assumed -------------------------------


def test_t5_vllm_pair_untouched_under_default():
    """Parent D6: cf-105's two entries stay under `default:` with their exact
    urls and datasource; the `default` provider block itself stays name+path
    intact (C02 APPENDS, never edits). Preserve pin — green today, must stay
    green."""
    default = _dashboards().get("default") or {}
    for key, url in (("vllm-performance-statistics", VLLM_PERF_URL), ("vllm-query-statistics", VLLM_QUERY_URL)):
        entry = default.get(key)
        assert isinstance(entry, dict) and entry.get("url") == url, (
            f"cf-145 C02 AC3 (preserve): dashboards.default.{key} moved or changed — parent D6 keeps the "
            "vllm lane byte-untouched; the URL drift:\n  got:  {(entry or {}).get('url')!r}\n  want: {url!r}"
        )
        assert entry.get("datasource") == "Prometheus", f"cf-145 C02: dashboards.default.{key}.datasource changed"
    provs = [p for p in _providers() if p.get("name") == "default"]
    assert len(provs) == 1 and (provs[0].get("options") or {}).get("path") == "/var/lib/grafana/dashboards/default", (
        "cf-145 C02 AC3 (preserve): the default provider block changed — C02 appends beside it"
    )


@helm_skip
def test_t5_rendered_script_still_writes_vllm_to_default_path():
    """Render-level half of the D6 pin: the two vllm curls keep landing under
    /var/lib/grafana/dashboards/default (they still do today; adding the
    inference provider must not re-home them)."""
    script = _grafana_render().get("download_dashboards.sh") or ""
    blocks = {key: [b for b in _split_curl_blocks(script) if url in b]
              for key, url in (("vllm-performance-statistics", VLLM_PERF_URL),
                               ("vllm-query-statistics", VLLM_QUERY_URL))}
    for key, bl in blocks.items():
        assert bl, f"cf-145 C02 AC3 (preserve): download script lost the {key} curl block"
        assert f'> "/var/lib/grafana/dashboards/default/{key}.json"' in bl[0], (
            f"cf-145 C02 AC3 (preserve): {key} no longer writes to the default path — "
            "its provider half must still resolve to `default` (R8 name==key law)"
        )
