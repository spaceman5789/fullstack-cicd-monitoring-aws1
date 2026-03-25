"""
Full-stack Deploy API — FastAPI application with Prometheus metrics.
Integrates with PostgreSQL (RDS) and exposes /metrics for Prometheus scraping.
"""

import os
import time
import logging

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import (
    Counter,
    Histogram,
    Gauge,
    generate_latest,
    CONTENT_TYPE_LATEST,
)
import psycopg2
from psycopg2.extras import RealDictCursor
from contextlib import asynccontextmanager

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "appdb")
DB_USER = os.getenv("DB_USER", "appuser")
DB_PASSWORD = os.getenv("DB_PASSWORD", "apppass")

APP_VERSION = os.getenv("APP_VERSION", "0.1.0")
APP_ENV = os.getenv("APP_ENV", "development")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Prometheus Metrics
# ---------------------------------------------------------------------------
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status_code"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)
ACTIVE_REQUESTS = Gauge(
    "http_active_requests",
    "Number of active HTTP requests",
)
DB_CONNECTION_ERRORS = Counter(
    "db_connection_errors_total",
    "Total database connection errors",
)
APP_INFO = Gauge(
    "app_info",
    "Application metadata",
    ["version", "environment"],
)
APP_INFO.labels(version=APP_VERSION, environment=APP_ENV).set(1)

# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------
def get_db_connection():
    """Create a new database connection."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=5,
        )
        return conn
    except psycopg2.OperationalError as exc:
        DB_CONNECTION_ERRORS.inc()
        logger.error("Database connection failed: %s", exc)
        raise


def init_db():
    """Initialise the database schema (idempotent)."""
    retries = 5
    for attempt in range(1, retries + 1):
        try:
            conn = get_db_connection()
            with conn.cursor() as cur:
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS items (
                        id          SERIAL PRIMARY KEY,
                        name        VARCHAR(255) NOT NULL,
                        description TEXT,
                        created_at  TIMESTAMP DEFAULT NOW()
                    );
                    """
                )
            conn.commit()
            conn.close()
            logger.info("Database initialised successfully")
            return
        except Exception as exc:
            logger.warning(
                "DB init attempt %d/%d failed: %s", attempt, retries, exc
            )
            if attempt < retries:
                time.sleep(2 ** attempt)
    logger.error("Could not initialise database after %d attempts", retries)


# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(
    title="Fullstack Deploy API",
    version=APP_VERSION,
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Middleware — metrics collection
# ---------------------------------------------------------------------------
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)

    ACTIVE_REQUESTS.inc()
    start = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - start

    endpoint = request.url.path
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=endpoint,
        status_code=response.status_code,
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=endpoint,
    ).observe(elapsed)
    ACTIVE_REQUESTS.dec()

    return response


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.get("/")
async def root():
    return {
        "service": "fullstack-deploy-api",
        "version": APP_VERSION,
        "environment": APP_ENV,
    }


@app.get("/health")
async def health():
    """Liveness probe — always returns 200 if the process is running."""
    return {"status": "healthy", "uptime_seconds": time.process_time()}


@app.get("/ready")
async def readiness():
    """Readiness probe — checks database connectivity."""
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        return {"status": "ready"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database unavailable: {exc}")


@app.get("/api/items")
async def list_items():
    conn = get_db_connection()
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT id, name, description, created_at FROM items ORDER BY id")
        items = cur.fetchall()
    conn.close()
    return {"items": items, "count": len(items)}


@app.post("/api/items", status_code=201)
async def create_item(request: Request):
    body = await request.json()
    name = body.get("name")
    if not name:
        raise HTTPException(status_code=400, detail="Field 'name' is required")

    description = body.get("description", "")
    conn = get_db_connection()
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "INSERT INTO items (name, description) VALUES (%s, %s) RETURNING id, name, description, created_at",
            (name, description),
        )
        item = cur.fetchone()
    conn.commit()
    conn.close()
    return item


@app.get("/api/items/{item_id}")
async def get_item(item_id: int):
    conn = get_db_connection()
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT id, name, description, created_at FROM items WHERE id = %s",
            (item_id,),
        )
        item = cur.fetchone()
    conn.close()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item


@app.delete("/api/items/{item_id}")
async def delete_item(item_id: int):
    conn = get_db_connection()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM items WHERE id = %s RETURNING id", (item_id,))
        deleted = cur.fetchone()
    conn.commit()
    conn.close()
    if not deleted:
        raise HTTPException(status_code=404, detail="Item not found")
    return {"deleted": True, "id": item_id}


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint."""
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )
