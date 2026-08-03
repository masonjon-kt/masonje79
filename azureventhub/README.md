# Azure Service Bus File Poster

This project posts files to Azure Service Bus based on a JSON config file.

It supports:
- Queue or topic sender targets.
- Multiple file sources.
- Full file paths in config (no base_dir).
- Chunked file transfer for larger files.
- Location metadata attached to every message.

## Files

- `servicebus_file_poster.py`: Main script.
- `servicebus_config.json`: Active config.
- `servicebus_config.example.json`: Config template.
- `servicebus_requirements.txt`: Python dependencies.

## Prerequisites

- Python 3.10+
- Azure Service Bus namespace with a queue or topic.
- Connection string with send permissions.

## Install

From this folder:

```bash
pip install -r servicebus_requirements.txt
```

## Configure

Set your connection string as an environment variable:

```bash
export AZURE_SERVICEBUS_CONNECTION_STRING='Endpoint=sb://...;SharedAccessKeyName=...;SharedAccessKey=...'
```

Then update `servicebus_config.json`.

### Config shape

```json
{
  "service_bus": {
    "connection_string_env": "AZURE_SERVICEBUS_CONNECTION_STRING",
    "entity_type": "queue",
    "entity_name": "ingress-files"
  },
  "send": {
    "chunk_size": 180000,
    "include_eof": true
  },
  "sources": [
    {
      "source_name": "store_001",
      "files": [
        "/full/path/to/KRPINPAD.DAT",
        "/full/path/to/INVDISC.RPT"
      ],
      "location": {
        "site": "store_001",
        "city": "Nashville",
        "region": "TN",
        "system": "pos-backoffice"
      }
    }
  ]
}
```

## Location Metadata

Each source must include a non-empty `location` object.

That location data is sent in two places for every message:

1. Message body: `location`
2. Message application properties: `location_tag` (derived from `location.site` when present)

This lets consumers route/filter quickly by properties and still retain full location details in the message body.

## Run

From this folder:

```bash
python servicebus_file_poster.py --config servicebus_config.json
```

## Message Types

The script sends:

- `file_chunk`: one message per file chunk.
- `file_eof`: optional end-of-file marker if `send.include_eof` is `true`.

### file_chunk body example

```json
{
  "message_type": "file_chunk",
  "source_name": "store_001",
  "location": {
    "site": "store_001",
    "city": "Nashville",
    "region": "TN",
    "system": "pos-backoffice"
  },
  "file": {
    "name": "KRPINPAD.DAT",
    "size": 12345,
    "seq": 0,
    "total_chunks": 2,
    "data_b64": "..."
  }
}
```

### Application properties example

```json
{
  "message_type": "file_chunk",
  "source_name": "store_001",
  "file_name": "KRPINPAD.DAT",
  "seq": 0,
  "total_chunks": 2,
  "location_tag": "store_001"
}
```

## Notes

- `sources[].files` must contain full absolute file paths.
- If no files are found for a source, that source is skipped.
- If a configured file path does not exist, the script raises a config error.
