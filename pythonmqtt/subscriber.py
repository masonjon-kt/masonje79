import argparse
import os
import signal
import sys

import paho.mqtt.client as mqtt


DEFAULT_HOST = os.getenv("MQTT_HOST", "localhost")
DEFAULT_PORT = int(os.getenv("MQTT_PORT", "1883"))
DEFAULT_USERNAME = os.getenv("MQTT_USERNAME", "tunaposuser")
DEFAULT_PASSWORD = os.getenv("MQTT_PASSWORD", "tunapospass")
DEFAULT_TOPIC = os.getenv("MQTT_TOPIC", "tunapos")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Subscribe to MQTT topic tunapos.")
    parser.add_argument("--host", default=DEFAULT_HOST, help="MQTT broker host.")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="MQTT broker port.")
    parser.add_argument("--username", default=DEFAULT_USERNAME, help="MQTT username.")
    parser.add_argument("--password", default=DEFAULT_PASSWORD, help="MQTT password.")
    parser.add_argument("--topic", default=DEFAULT_TOPIC, help="MQTT topic.")
    return parser


def main() -> int:
    args = build_parser().parse_args()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.username_pw_set(args.username, args.password)
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    def on_connect(client: mqtt.Client, _userdata, _flags, reason_code, _properties):
        if reason_code == 0:
            print(f"Connected. Subscribing to '{args.topic}'...")
            client.subscribe(args.topic, qos=1)
        else:
            print(f"Connection failed with code {reason_code}")

    def on_message(_client: mqtt.Client, _userdata, msg: mqtt.MQTTMessage):
        payload = msg.payload.decode("utf-8", errors="replace")
        print(f"[{msg.topic}] {payload}")
        print("Waiting for next message...")

    def on_disconnect(_client: mqtt.Client, _userdata, _flags, reason_code, _properties):
        if reason_code != 0:
            print(f"Disconnected (code {reason_code}). Retrying...")

    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    try:
        client.connect(args.host, args.port, keepalive=60)
    except Exception as exc:
        print(f"Failed to connect to MQTT broker: {exc}")
        return 1

    def handle_stop(_signum, _frame):
        print("\nStopping subscriber...")
        client.disconnect()

    signal.signal(signal.SIGINT, handle_stop)
    signal.signal(signal.SIGTERM, handle_stop)

    print("Waiting for messages. Press Ctrl+C to stop.")
    client.loop_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
