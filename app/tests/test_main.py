"""Unit tests for the FastAPI application.

Database-dependent endpoints are tested with mocked psycopg2 connections.
Non-DB endpoints (health, root, metrics) are tested directly.
"""

import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

# Patch DB init before importing app
with patch("src.main.init_db"):
    from src.main import app

client = TestClient(app)


# ── Health & Root ────────────────────────────────────────────────
class TestHealthEndpoints:
    def test_root(self):
        resp = client.get("/")
        assert resp.status_code == 200
        data = resp.json()
        assert data["service"] == "fullstack-deploy-api"
        assert "version" in data

    def test_health(self):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "healthy"

    def test_metrics(self):
        resp = client.get("/metrics")
        assert resp.status_code == 200
        assert "http_requests_total" in resp.text


# ── Readiness ────────────────────────────────────────────────────
class TestReadiness:
    @patch("src.main.get_db_connection")
    def test_ready_ok(self, mock_conn):
        mock_cur = MagicMock()
        mock_conn.return_value.__enter__ = lambda s: s
        mock_conn.return_value.__exit__ = MagicMock(return_value=False)
        mock_conn.return_value.cursor.return_value.__enter__ = lambda s: mock_cur
        mock_conn.return_value.cursor.return_value.__exit__ = MagicMock(return_value=False)

        resp = client.get("/ready")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ready"

    @patch("src.main.get_db_connection", side_effect=Exception("DB down"))
    def test_ready_fail(self, _):
        resp = client.get("/ready")
        assert resp.status_code == 503


# ── Items CRUD ───────────────────────────────────────────────────
class TestItemsCRUD:
    @patch("src.main.get_db_connection")
    def test_list_items_empty(self, mock_conn):
        mock_cur = MagicMock()
        mock_cur.fetchall.return_value = []
        mock_conn.return_value.cursor.return_value.__enter__ = lambda s: mock_cur
        mock_conn.return_value.cursor.return_value.__exit__ = MagicMock(return_value=False)

        resp = client.get("/api/items")
        assert resp.status_code == 200
        assert resp.json()["count"] == 0

    @patch("src.main.get_db_connection")
    def test_create_item(self, mock_conn):
        mock_cur = MagicMock()
        mock_cur.fetchone.return_value = {
            "id": 1,
            "name": "Test",
            "description": "desc",
            "created_at": "2026-01-01T00:00:00",
        }
        mock_conn.return_value.cursor.return_value.__enter__ = lambda s: mock_cur
        mock_conn.return_value.cursor.return_value.__exit__ = MagicMock(return_value=False)

        resp = client.post("/api/items", json={"name": "Test", "description": "desc"})
        assert resp.status_code == 201
        assert resp.json()["name"] == "Test"

    def test_create_item_missing_name(self):
        resp = client.post("/api/items", json={"description": "no name"})
        assert resp.status_code == 400

    @patch("src.main.get_db_connection")
    def test_get_item(self, mock_conn):
        mock_cur = MagicMock()
        mock_cur.fetchone.return_value = {
            "id": 1,
            "name": "Test",
            "description": "",
            "created_at": "2026-01-01T00:00:00",
        }
        mock_conn.return_value.cursor.return_value.__enter__ = lambda s: mock_cur
        mock_conn.return_value.cursor.return_value.__exit__ = MagicMock(return_value=False)

        resp = client.get("/api/items/1")
        assert resp.status_code == 200

    @patch("src.main.get_db_connection")
    def test_get_item_not_found(self, mock_conn):
        mock_cur = MagicMock()
        mock_cur.fetchone.return_value = None
        mock_conn.return_value.cursor.return_value.__enter__ = lambda s: mock_cur
        mock_conn.return_value.cursor.return_value.__exit__ = MagicMock(return_value=False)

        resp = client.get("/api/items/999")
        assert resp.status_code == 404

    @patch("src.main.get_db_connection")
    def test_delete_item(self, mock_conn):
        mock_cur = MagicMock()
        mock_cur.fetchone.return_value = (1,)
        mock_conn.return_value.cursor.return_value.__enter__ = lambda s: mock_cur
        mock_conn.return_value.cursor.return_value.__exit__ = MagicMock(return_value=False)

        resp = client.delete("/api/items/1")
        assert resp.status_code == 200
        assert resp.json()["deleted"] is True

    @patch("src.main.get_db_connection")
    def test_delete_item_not_found(self, mock_conn):
        mock_cur = MagicMock()
        mock_cur.fetchone.return_value = None
        mock_conn.return_value.cursor.return_value.__enter__ = lambda s: mock_cur
        mock_conn.return_value.cursor.return_value.__exit__ = MagicMock(return_value=False)

        resp = client.delete("/api/items/999")
        assert resp.status_code == 404
