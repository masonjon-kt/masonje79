import argparse
import os
import sys

import paho.mqtt.client as mqtt


DEFAULT_HOST = os.getenv("MQTT_HOST", "localhost")
DEFAULT_PORT = int(os.getenv("MQTT_PORT", "1883"))
DEFAULT_USERNAME = os.getenv("MQTT_USERNAME", "tunaposuser")
DEFAULT_PASSWORD = os.getenv("MQTT_PASSWORD", "tunapospass")
DEFAULT_TOPIC = os.getenv("MQTT_TOPIC", "tunapos")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Publish a message to MQTT topic tunapos.")
    parser.add_argument("message", nargs="?", help="Message payload to publish.")
    parser.add_argument("--host", default=DEFAULT_HOST, help="MQTT broker host.")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="MQTT broker port.")
    parser.add_argument("--username", default=DEFAULT_USERNAME, help="MQTT username.")
    parser.add_argument("--password", default=DEFAULT_PASSWORD, help="MQTT password.")
    parser.add_argument("--topic", default=DEFAULT_TOPIC, help="MQTT topic.")
    return parser


def main() -> int:
    args = build_parser().parse_args()

    message = args.message
    if message is None:
        message = input("Enter message to send: ").strip()

    if not message:
        print("Message is empty. Nothing sent.")
        return 1

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.username_pw_set(args.username, args.password)

    try:
        client.connect(args.host, args.port, keepalive=60)
    except Exception as exc:
        print(f"Failed to connect to MQTT broker: {exc}")
        return 1

    client.loop_start()

    result = client.publish(args.topic, payload=message, qos=1)
    result.wait_for_publish(timeout=5.0)

    if result.rc != mqtt.MQTT_ERR_SUCCESS:
        client.loop_stop()
        client.disconnect()
        print(f"Publish failed with code {result.rc}")
        return 1

    if not result.is_published():
        client.loop_stop()
        client.disconnect()
        print("Publish timed out waiting for broker acknowledgement.")
        return 1

    print(f"Published to '{args.topic}': {message}")
    client.loop_stop()
    client.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
