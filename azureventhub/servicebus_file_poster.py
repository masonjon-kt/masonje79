#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import math
import os
import time
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterator, List, Tuple

import requests


class ConfigError(ValueError):
    pass


@dataclass
class ServiceBusConfig:
    connection_string: str
    entity_type: str
    entity_name: str


@dataclass
class SenderConfig:
    chunk_size: int
    include_eof: bool


@dataclass
class SourceConfig:
    source_name: str
    files: List[str]
    location: Dict[str, str]


def _parse_connection_string(conn_str: str) -> Tuple[str, str, str]:
    """Return (namespace_host, key_name, key) from a Service Bus connection string."""
    parts: Dict[str, str] = {}
    for segment in conn_str.strip().split(";"):
        key, _, value = segment.partition("=")
        if key:
            parts[key.strip()] = value.strip()

    endpoint = parts.get("Endpoint", "")
    namespace = endpoint.replace("sb://", "").rstrip("/")
    if not namespace:
        raise ConfigError("Cannot parse namespace from connection string Endpoint")

    key_name = parts.get("SharedAccessKeyName", "")
    key = parts.get("SharedAccessKey", "")
    if not key_name or not key:
        raise ConfigError("Connection string is missing SharedAccessKeyName or SharedAccessKey")

    return namespace, key_name, key


def _sas_token(resource_uri: str, key_name: str, key: str, ttl_seconds: int = 3600) -> str:
    expiry = str(int(time.time()) + ttl_seconds)
    string_to_sign = urllib.parse.quote_plus(resource_uri) + "\n" + expiry
    signature = base64.b64encode(
        hmac.new(key.encode("utf-8"), string_to_sign.encode("utf-8"), hashlib.sha256).digest()
    ).decode("ascii")
    return (
        f"SharedAccessSignature sr={urllib.parse.quote_plus(resource_uri)}"
        f"&sig={urllib.parse.quote_plus(signature)}"
        f"&se={expiry}"
        f"&skn={key_name}"
    )


def load_config(path: str) -> tuple[ServiceBusConfig, SenderConfig, List[SourceConfig]]:
    config_path = Path(path).expanduser().resolve()
    if not config_path.exists():
        raise ConfigError(f"Config file not found: {config_path}")

    with config_path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)

    sb_raw = raw.get("service_bus") or {}
    conn_string = sb_raw.get("connection_string")
    conn_env = sb_raw.get("connection_string_env")

    if not conn_string and conn_env:
        conn_string = os.environ.get(conn_env)

    if not conn_string:
        raise ConfigError(
            "Missing service_bus.connection_string or service_bus.connection_string_env"
        )

    entity_type = (sb_raw.get("entity_type") or "queue").lower()
    if entity_type not in {"queue", "topic"}:
        raise ConfigError("service_bus.entity_type must be 'queue' or 'topic'")

    entity_name = sb_raw.get("entity_name")
    if not entity_name:
        raise ConfigError("service_bus.entity_name is required")

    sender_raw = raw.get("send") or {}
    sender = SenderConfig(
        chunk_size=int(sender_raw.get("chunk_size", 180000)),
        include_eof=bool(sender_raw.get("include_eof", True)),
    )

    src_raw = raw.get("sources")
    if not isinstance(src_raw, list) or not src_raw:
        raise ConfigError("sources must be a non-empty array")

    sources: List[SourceConfig] = []
    for idx, item in enumerate(src_raw):
        if not isinstance(item, dict):
            raise ConfigError(f"sources[{idx}] must be an object")

        source_name = item.get("source_name") or item.get("name") or f"source_{idx}"
        files = item.get("files") or []
        location = item.get("location") or {}

        if not isinstance(files, list) or not files:
            raise ConfigError(f"sources[{idx}].files must be a non-empty array of full paths")

        if not isinstance(location, dict) or not location:
            raise ConfigError(f"sources[{idx}].location must be a non-empty object")

        sources.append(
            SourceConfig(
                source_name=source_name,
                files=files,
                location={str(k): str(v) for k, v in location.items()},
            )
        )

    return (
        ServiceBusConfig(
            connection_string=conn_string,
            entity_type=entity_type,
            entity_name=entity_name,
        ),
        sender,
        sources,
    )


def find_files(source: SourceConfig) -> List[Path]:
    selected: List[Path] = []

    for path_str in source.files:
        candidate = Path(path_str).expanduser()
        if not candidate.is_absolute():
            raise ConfigError(f"Configured file path must be absolute: {candidate}")
        candidate = candidate.resolve()
        if not candidate.exists() or not candidate.is_file():
            raise ConfigError(f"Configured file not found: {candidate}")
        selected.append(candidate)

    # Keep order stable and remove duplicates.
    deduped: List[Path] = []
    seen: set[Path] = set()
    for p in selected:
        if p not in seen:
            seen.add(p)
            deduped.append(p)

    return deduped


def iter_chunks(path: Path, chunk_size: int) -> Iterator[tuple[int, bytes]]:
    with path.open("rb") as handle:
        i = 0
        while True:
            data = handle.read(chunk_size)
            if not data:
                break
            yield i, data
            i += 1


def _post_message(
    session: requests.Session,
    url: str,
    token: str,
    body: str,
    user_properties: Dict[str, str],
) -> None:
    headers = {
        "Authorization": token,
        "Content-Type": "application/json",
    }
    headers.update(user_properties)
    response = session.post(url, data=body.encode("utf-8"), headers=headers)
    response.raise_for_status()


def send_one_file(
    session: requests.Session,
    url: str,
    token: str,
    path: Path,
    source: SourceConfig,
    send_cfg: SenderConfig,
) -> int:
    file_size = path.stat().st_size
    total_chunks = max(1, math.ceil(file_size / send_cfg.chunk_size))

    sent = 0
    for seq, chunk in iter_chunks(path, send_cfg.chunk_size):
        body = {
            "message_type": "file_chunk",
            "source_name": source.source_name,
            "location": source.location,
            "file": {
                "name": path.name,
                "size": file_size,
                "seq": seq,
                "total_chunks": total_chunks,
                "data_b64": base64.b64encode(chunk).decode("ascii"),
            },
        }
        user_props = {
            "message_type": "file_chunk",
            "source_name": source.source_name,
            "file_name": path.name,
            "seq": str(seq),
            "total_chunks": str(total_chunks),
            "location_tag": source.location.get("site", source.source_name),
        }
        _post_message(session, url, token, json.dumps(body), user_props)
        sent += 1

    if send_cfg.include_eof:
        eof_body = {
            "message_type": "file_eof",
            "source_name": source.source_name,
            "location": source.location,
            "file": {
                "name": path.name,
                "size": file_size,
                "total_chunks": total_chunks,
            },
        }
        eof_props = {
            "message_type": "file_eof",
            "source_name": source.source_name,
            "file_name": path.name,
            "location_tag": source.location.get("site", source.source_name),
        }
        _post_message(session, url, token, json.dumps(eof_body), eof_props)

    return sent


def run(config_path: str) -> Dict[str, int]:
    sb_cfg, send_cfg, sources = load_config(config_path)

    namespace, key_name, key = _parse_connection_string(sb_cfg.connection_string)
    base_url = f"https://{namespace}/{sb_cfg.entity_name}/messages"
    resource_uri = f"https://{namespace}/{sb_cfg.entity_name}"
    token = _sas_token(resource_uri, key_name, key)

    summary: Dict[str, int] = {}
    with requests.Session() as session:
        for source in sources:
            files = find_files(source)
            if not files:
                continue
            for file_path in files:
                key_label = f"{source.source_name}:{file_path.name}"
                summary[key_label] = send_one_file(
                    session, base_url, token, file_path, source, send_cfg
                )

    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Post files to Azure Service Bus based on a JSON config"
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Path to JSON config file",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    results = run(args.config)
    print(json.dumps({"status": "ok", "files_sent": results}, indent=2))


if __name__ == "__main__":
    main()
