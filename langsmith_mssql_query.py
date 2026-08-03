#!/usr/bin/env python3
"""
Run a SQL Server query and record the execution as a LangSmith trace.

Setup:
1) Install packages:
    pip install langsmith sqlalchemy pyodbc python-dotenv

2) Create a .env file in this folder:
    LANGSMITH_API_KEY=<your-langsmith-api-key>
    LANGSMITH_TRACING=true
    LANGSMITH_PROJECT=mssql-query-project

    MSSQL_SERVER=your-sql-server-host
    MSSQL_DATABASE=your_database
    MSSQL_USERNAME=your_username
    MSSQL_PASSWORD=your_password
    MSSQL_DRIVER=ODBC Driver 18 for SQL Server
    MSSQL_AUTHENTICATION=SqlPassword
    MSSQL_QUERY=SELECT @@VERSION AS sql_server_version

Authentication modes:
    SqlPassword
        Use SQL Server username/password.
    ActiveDirectoryPassword
        Use a Microsoft Entra username/password, typically user@domain.
    ActiveDirectoryIntegrated
        Use Kerberos/integrated auth on Linux. Requires a valid Kerberos ticket.
        UID/PWD are not sent in this mode.

3) Run:
   python langsmith_mssql_query.py
"""

import os
import urllib.parse
from typing import Any

from langsmith import traceable
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine


def resolve_mssql_driver() -> str:
    """Return a usable SQL Server ODBC driver name."""
    explicit_driver = os.getenv("MSSQL_DRIVER")

    try:
        import pyodbc
    except ImportError as exc:
        if "libodbc.so.2" in str(exc):
            raise RuntimeError(
                "Missing system ODBC runtime (libodbc.so.2). On Ubuntu/Debian run: "
                "sudo apt-get update && sudo apt-get install -y libodbc2 unixodbc odbcinst"
            ) from exc
        raise

    installed_drivers = set(pyodbc.drivers())

    if explicit_driver:
        if explicit_driver not in installed_drivers:
            available = ", ".join(sorted(installed_drivers)) or "none"
            raise RuntimeError(
                f"MSSQL_DRIVER is set to '{explicit_driver}', but it is not installed. "
                f"Available ODBC drivers: {available}"
            )
        return explicit_driver

    for candidate in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
        if candidate in installed_drivers:
            return candidate

    raise RuntimeError(
        "No Microsoft SQL Server ODBC driver is installed. "
        "On Ubuntu, install one with: "
        "sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18"
    )


def normalize_server_name(server: str) -> str:
    """Convert common host:port input into a SQL Server ODBC-compatible server string."""
    if server.startswith("tcp:") or "," in server:
        return server

    host, separator, port = server.rpartition(":")
    if separator and host and port.isdigit():
        return f"tcp:{host},{port}"

    return server


def build_auth_settings() -> tuple[str, list[str]]:
    """Build auth-specific ODBC settings and return missing required env vars."""
    authentication = os.getenv("MSSQL_AUTHENTICATION", "SqlPassword").strip() or "SqlPassword"
    username = os.getenv("MSSQL_USERNAME")
    password = os.getenv("MSSQL_PASSWORD")

    if authentication == "ActiveDirectoryIntegrated":
        return f"Authentication={authentication};", []

    missing = [
        key
        for key, value in {
            "MSSQL_USERNAME": username,
            "MSSQL_PASSWORD": password,
        }.items()
        if not value
    ]
    if missing:
        return "", missing

    auth_settings = f"UID={username};PWD={password};"
    if authentication != "SqlPassword":
        auth_settings += f"Authentication={authentication};"

    return auth_settings, []


def build_mssql_engine() -> Engine:
    """Build and return a SQLAlchemy engine for SQL Server via pyodbc."""
    server = os.getenv("MSSQL_SERVER")
    database = os.getenv("MSSQL_DATABASE")
    driver = resolve_mssql_driver()
    auth_settings, auth_missing = build_auth_settings()

    missing = [
        key
        for key, value in {
            "MSSQL_SERVER": server,
            "MSSQL_DATABASE": database,
        }.items()
        if not value
    ]
    missing.extend(auth_missing)
    if missing:
        raise ValueError(f"Missing required environment variables: {', '.join(missing)}")

    server = normalize_server_name(server)

    odbc_connection = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"{auth_settings}"
        "Encrypt=yes;"
        "TrustServerCertificate=yes;"
    )

    connect_str = urllib.parse.quote_plus(odbc_connection)

    try:
        return create_engine(f"mssql+pyodbc:///?odbc_connect={connect_str}", future=True)
    except ImportError as exc:
        if "libodbc.so.2" in str(exc):
            raise RuntimeError(
                "Missing system ODBC runtime (libodbc.so.2). On Ubuntu/Debian run: "
                "sudo apt-get update && sudo apt-get install -y libodbc2 unixodbc odbcinst"
            ) from exc
        raise


@traceable(name="query_mssql")
def run_query(engine: Engine, sql: str) -> list[dict[str, Any]]:
    """Execute a query and return rows as dictionaries."""
    with engine.connect() as connection:
        result = connection.execute(text(sql))
        rows = [dict(row._mapping) for row in result]
    return rows


def main() -> None:
    load_dotenv()

    # This default query is safe and works without schema knowledge.
    sql = os.getenv("MSSQL_QUERY", "SELECT @@VERSION AS sql_server_version")

    engine = build_mssql_engine()
    rows = run_query(engine, sql)

    print(f"Returned {len(rows)} row(s)")
    for idx, row in enumerate(rows, start=1):
        print(f"Row {idx}: {row}")


if __name__ == "__main__":
    main()
