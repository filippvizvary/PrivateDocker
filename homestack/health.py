"""HomeStack — Post-install health checks.

Reads ``test.yaml`` from the installed app directory (copied from catalog
during install) and validates the app is working correctly:

1. Wait ``startup_time`` seconds for containers to reach healthy state.
2. Run HTTP health checks via ``urllib.request``.
3. Run exec checks via ``docker compose exec``.
"""

from __future__ import annotations

import time
import urllib.request
import urllib.error
from pathlib import Path

import click

from homestack import core
from homestack.yaml_parser import (
    get_startup_time, parse_health_checks, parse_exec_checks,
    HealthCheck, ExecCheck,
)


def run_health_checks(app_name: str, install_dir: str | Path) -> bool:
    """Run all health checks for an app.  Returns True if all pass.

    The ``test.yaml`` must be present in *install_dir*.  If it's missing,
    the check is skipped with a warning (returns True).
    """
    install_dir = Path(install_dir)
    test_yaml = install_dir / "test.yaml"

    if not test_yaml.is_file():
        core.warn(f"No test.yaml found for {app_name}, skipping health checks")
        return True

    startup = get_startup_time(str(test_yaml))
    http_checks = parse_health_checks(str(test_yaml))
    exec_checks = parse_exec_checks(str(test_yaml))

    if not http_checks and not exec_checks:
        core.warn(f"No health checks defined for {app_name}")
        return True

    # Phase 1: Wait for containers to settle
    core.step(f"Waiting {startup}s for {app_name} to start")
    _wait_for_healthy(install_dir, timeout=startup)

    all_ok = True

    # Phase 2: HTTP checks (generous retries to cover slow app init)
    for hc in http_checks:
        if not _run_http_check(app_name, hc, retries=10, retry_delay=5):
            all_ok = False

    # Phase 3: Exec checks
    for ec in exec_checks:
        if not _run_exec_check(app_name, install_dir, ec):
            all_ok = False

    return all_ok


def _wait_for_healthy(install_dir: Path, timeout: int) -> None:
    """Poll ``docker compose ps`` until containers are up or *timeout* expires."""
    deadline = time.monotonic() + timeout
    interval = 2
    while time.monotonic() < deadline:
        try:
            result = core.compose_cmd(
                install_dir, "ps", "--format", "{{.Status}}",
                capture=True, check=False, quiet_err=True,
            )
            statuses = result.stdout.strip().splitlines() if result.stdout else []
            if statuses and all("Up" in s or "running" in s for s in statuses):
                core.success("Containers are running")
                return
        except Exception:
            pass
        time.sleep(interval)

    core.warn("Timeout waiting for containers — proceeding with checks anyway")


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Don't follow redirects — let us check the actual status code."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(newurl, code, msg, headers, fp)


def _run_http_check(app_name: str, hc: HealthCheck, retries: int = 5,
                    retry_delay: int = 3) -> bool:
    """Run a single HTTP health check with retries. Returns True on pass."""
    core.step(f"Checking {hc.url}")

    import ssl
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    # Handle redirects manually to check status codes accurately
    import urllib.request
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ctx),
        _NoRedirectHandler(),
    )

    last_err: str = ""
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(hc.url, method=hc.method)
            resp = opener.open(req, timeout=hc.timeout)
            status = resp.getcode()
            body = resp.read().decode("utf-8", errors="replace")

            if status != hc.expected_status:
                last_err = f"returned {status}, expected {hc.expected_status}"
                if attempt < retries:
                    time.sleep(retry_delay)
                    continue
                core.error(f"Health check failed: {hc.url} {last_err}")
                return False

            if hc.body_contains and hc.body_contains not in body:
                last_err = f"body does not contain '{hc.body_contains}'"
                if attempt < retries:
                    time.sleep(retry_delay)
                    continue
                core.error(f"Health check failed: {hc.url} {last_err}")
                return False

            core.success(f"{hc.url} → {status} OK")
            return True

        except urllib.error.HTTPError as e:
            if e.code == hc.expected_status:
                core.success(f"{hc.url} → {e.code} OK")
                return True
            last_err = f"returned {e.code}"

        except Exception as e:
            last_err = str(e)

        if attempt < retries:
            time.sleep(retry_delay)

    core.error(f"Health check failed: {hc.url} — {last_err}")
    return False


def _run_exec_check(app_name: str, install_dir: Path, ec: ExecCheck) -> bool:
    """Run a single exec check inside a container. Returns True on pass."""
    core.step(f"Exec check: {ec.container} → {ec.command}")
    try:
        result = core.compose_cmd(
            install_dir, "exec", "-T", ec.container, "sh", "-c", ec.command,
            capture=True, check=False, quiet_err=True,
        )
        output = (result.stdout or "").strip()

        if result.returncode != 0:
            core.error(f"Exec check failed: {ec.command} exited {result.returncode}")
            return False

        if ec.expected_output and ec.expected_output not in output:
            core.error(
                f"Exec check failed: output does not contain '{ec.expected_output}'"
            )
            return False

        core.success(f"{ec.container}: {ec.command} → OK")
        return True

    except Exception as e:
        core.error(f"Exec check failed: {e}")
        return False
