"""Unit tests for homestack.health module."""

from __future__ import annotations

import http.server
import threading
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from homestack.health import run_health_checks, _run_http_check, _run_exec_check
from homestack.yaml_parser import HealthCheck, ExecCheck


class TestRunHealthChecks:
    def test_missing_test_yaml_returns_true(self, tmp_homestack):
        """If no test.yaml exists, health checks are skipped (returns True)."""
        install_dir = tmp_homestack / "installed" / "testapp"
        install_dir.mkdir(parents=True)
        # No test.yaml
        result = run_health_checks("testapp", install_dir)
        assert result is True

    def test_empty_checks_returns_true(self, tmp_homestack):
        """If test.yaml has no health or exec checks, returns True."""
        install_dir = tmp_homestack / "installed" / "testapp"
        install_dir.mkdir(parents=True)
        test_yaml = install_dir / "test.yaml"
        test_yaml.write_text(
            "startup_time: 1\n"
            "health_checks: []\n"
            "exec_checks: []\n"
        )
        result = run_health_checks("testapp", install_dir)
        assert result is True


class TestRunHttpCheck:
    def test_successful_check(self):
        """HTTP check passes when server returns expected status."""
        handler = _make_handler(200, "ok")
        server = http.server.HTTPServer(("127.0.0.1", 0), handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.handle_request, daemon=True)
        thread.start()

        hc = HealthCheck(
            url=f"http://127.0.0.1:{port}/health",
            expected_status=200,
        )
        result = _run_http_check("testapp", hc, retries=1, retry_delay=0)
        assert result is True
        server.server_close()

    def test_wrong_status_fails(self):
        """HTTP check fails when status doesn't match."""
        handler = _make_handler(503, "error")
        server = http.server.HTTPServer(("127.0.0.1", 0), handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.handle_request, daemon=True)
        thread.start()

        hc = HealthCheck(
            url=f"http://127.0.0.1:{port}/health",
            expected_status=200,
        )
        result = _run_http_check("testapp", hc, retries=1, retry_delay=0)
        assert result is False
        server.server_close()

    def test_body_contains_passes(self):
        """HTTP check passes when body contains expected string."""
        handler = _make_handler(200, '{"status": "healthy"}')
        server = http.server.HTTPServer(("127.0.0.1", 0), handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.handle_request, daemon=True)
        thread.start()

        hc = HealthCheck(
            url=f"http://127.0.0.1:{port}/health",
            expected_status=200,
            body_contains="healthy",
        )
        result = _run_http_check("testapp", hc, retries=1, retry_delay=0)
        assert result is True
        server.server_close()

    def test_body_contains_fails(self):
        """HTTP check fails when body doesn't contain expected string."""
        handler = _make_handler(200, '{"status": "degraded"}')
        server = http.server.HTTPServer(("127.0.0.1", 0), handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.handle_request, daemon=True)
        thread.start()

        hc = HealthCheck(
            url=f"http://127.0.0.1:{port}/health",
            expected_status=200,
            body_contains="healthy",
        )
        result = _run_http_check("testapp", hc, retries=1, retry_delay=0)
        assert result is False
        server.server_close()

    def test_connection_refused_fails(self):
        """HTTP check fails when server is unreachable."""
        hc = HealthCheck(
            url="http://127.0.0.1:59876/health",
            expected_status=200,
            timeout=1,
        )
        result = _run_http_check("testapp", hc, retries=1, retry_delay=0)
        assert result is False

    def test_retries_on_failure(self):
        """HTTP check retries before giving up."""
        # Start a server that always returns 503
        handler = _make_handler(503, "error")
        server = http.server.HTTPServer(("127.0.0.1", 0), handler)
        port = server.server_address[1]
        # Handle multiple requests for retries
        thread = threading.Thread(
            target=lambda: [server.handle_request() for _ in range(3)],
            daemon=True,
        )
        thread.start()

        hc = HealthCheck(
            url=f"http://127.0.0.1:{port}/health",
            expected_status=200,
        )
        result = _run_http_check("testapp", hc, retries=3, retry_delay=0)
        assert result is False
        server.server_close()


class TestRunExecCheck:
    @patch("homestack.health.core.compose_cmd")
    def test_successful_exec(self, mock_compose):
        """Exec check passes when command succeeds with expected output."""
        mock_compose.return_value = MagicMock(returncode=0, stdout="PONG\n")
        ec = ExecCheck(
            container="redis",
            command="redis-cli ping",
            expected_output="PONG",
        )
        result = _run_exec_check("testapp", Path("/fake/dir"), ec)
        assert result is True

    @patch("homestack.health.core.compose_cmd")
    def test_nonzero_exit_fails(self, mock_compose):
        """Exec check fails when command returns non-zero."""
        mock_compose.return_value = MagicMock(returncode=1, stdout="")
        ec = ExecCheck(
            container="redis",
            command="redis-cli ping",
        )
        result = _run_exec_check("testapp", Path("/fake/dir"), ec)
        assert result is False

    @patch("homestack.health.core.compose_cmd")
    def test_missing_expected_output_fails(self, mock_compose):
        """Exec check fails when output doesn't contain expected string."""
        mock_compose.return_value = MagicMock(returncode=0, stdout="ERROR\n")
        ec = ExecCheck(
            container="redis",
            command="redis-cli ping",
            expected_output="PONG",
        )
        result = _run_exec_check("testapp", Path("/fake/dir"), ec)
        assert result is False

    @patch("homestack.health.core.compose_cmd")
    def test_no_expected_output_passes(self, mock_compose):
        """Exec check passes when no expected_output is specified."""
        mock_compose.return_value = MagicMock(returncode=0, stdout="anything\n")
        ec = ExecCheck(
            container="redis",
            command="redis-cli ping",
            expected_output="",
        )
        result = _run_exec_check("testapp", Path("/fake/dir"), ec)
        assert result is True


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_handler(status: int, body: str):
    """Create a simple HTTP handler that returns a fixed response."""
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(status)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(body.encode())

        def log_message(self, format, *args):
            pass  # Suppress log output during tests

    return Handler
