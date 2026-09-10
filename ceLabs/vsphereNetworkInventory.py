#!/usr/bin/env python3
"""Dump vSphere VM network inventory (NIC, MAC, IP, port, switch) as CSV to stdout.

Credentials come from the environment or a .env file next to this script:
    VSPHERE_HOST, VSPHERE_USER, VSPHERE_PASSWORD
"""

import csv
import os
import ssl
import sys
from pathlib import Path

from pyVim.connect import Disconnect, SmartConnect
from pyVmomi import vim

ENV_FILE = Path(__file__).resolve().with_name(".env")

FIELDS = [
    "vm_name",
    "power_state",
    "guest_hostname",
    "guest_os",
    "nic_label",
    "adapter_type",
    "mac_address",
    "connected",
    "network",
    "network_type",
    "switch",
    "port_key",
    "portgroup_key",
    "ip_addresses",
    "esxi_host",
]


def get_all_vms(content):
    view = content.viewManager.CreateContainerView(
        content.rootFolder, [vim.VirtualMachine], True
    )
    try:
        return sorted(view.view, key=lambda vm: (vm.name or "").lower())
    finally:
        view.Destroy()


def build_dvportgroup_map(content):
    """Map distributed portgroup key -> (portgroup name, dvSwitch name)."""
    view = content.viewManager.CreateContainerView(
        content.rootFolder, [vim.dvs.DistributedVirtualPortgroup], True
    )
    try:
        mapping = {}
        for pg in view.view:
            switch_name = ""
            try:
                switch_name = pg.config.distributedVirtualSwitch.name
            except Exception:
                pass
            mapping[pg.key] = (pg.name, switch_name)
        return mapping
    finally:
        view.Destroy()


def build_standard_portgroup_map(content):
    """Map standard portgroup name -> vSwitch name (per ESXi host)."""
    view = content.viewManager.CreateContainerView(
        content.rootFolder, [vim.HostSystem], True
    )
    try:
        mapping = {}
        for host in view.view:
            try:
                for pg in host.config.network.portgroup:
                    mapping[(host.name, pg.spec.name)] = pg.spec.vswitchName
            except Exception:
                continue
        return mapping
    finally:
        view.Destroy()


def guest_ips_by_mac(vm):
    """Map lowercase MAC -> comma separated IP list reported by VMware Tools."""
    ips = {}
    try:
        for nic in vm.guest.net or []:
            if not nic.macAddress:
                continue
            addrs = []
            if nic.ipConfig and nic.ipConfig.ipAddress:
                addrs = [
                    f"{a.ipAddress}/{a.prefixLength}" for a in nic.ipConfig.ipAddress
                ]
            elif nic.ipAddress:
                addrs = list(nic.ipAddress)
            ips[nic.macAddress.lower()] = " ".join(addrs)
    except Exception:
        pass
    return ips


def describe_backing(device, dvpg_map, std_pg_map, esxi_host):
    """Return (network, network_type, switch, port_key, portgroup_key)."""
    backing = device.backing

    if isinstance(backing, vim.vm.device.VirtualEthernetCard.DistributedVirtualPortBackingInfo):
        port = backing.port
        pg_key = port.portgroupKey or ""
        name, switch = dvpg_map.get(pg_key, ("", port.switchUuid or ""))
        return name, "dvportgroup", switch, port.portKey or "", pg_key

    if isinstance(backing, vim.vm.device.VirtualEthernetCard.OpaqueNetworkBackingInfo):
        return (
            backing.opaqueNetworkId or "",
            "opaque",
            backing.opaqueNetworkType or "",
            "",
            "",
        )

    if isinstance(backing, vim.vm.device.VirtualEthernetCard.NetworkBackingInfo):
        name = backing.deviceName or ""
        switch = std_pg_map.get((esxi_host, name), "")
        return name, "standard", switch, "", ""

    return "", type(backing).__name__ if backing else "", "", "", ""


def load_env_file(path=ENV_FILE):
    """Populate os.environ from a KEY=VALUE file; existing environment wins."""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip("'\"")
        if key and key not in os.environ:
            os.environ[key] = value


def main():
    load_env_file()
    host = os.environ.get("VSPHERE_HOST")
    user = os.environ.get("VSPHERE_USER")
    password = os.environ.get("VSPHERE_PASSWORD")
    if not (host and user and password):
        sys.exit(
            f"Set VSPHERE_HOST, VSPHERE_USER and VSPHERE_PASSWORD in the environment or {ENV_FILE}."
        )

    context = ssl._create_unverified_context()
    si = SmartConnect(host=host, user=user, pwd=password, sslContext=context)
    try:
        content = si.RetrieveContent()
        dvpg_map = build_dvportgroup_map(content)
        std_pg_map = build_standard_portgroup_map(content)

        writer = csv.DictWriter(sys.stdout, fieldnames=FIELDS)
        writer.writeheader()

        for vm in get_all_vms(content):
            try:
                esxi_host = vm.runtime.host.name if vm.runtime.host else ""
            except Exception:
                esxi_host = ""

            base = {
                "vm_name": vm.name,
                "power_state": vm.runtime.powerState,
                "guest_hostname": vm.guest.hostName or "" if vm.guest else "",
                "guest_os": (vm.config.guestFullName if vm.config else "") or "",
                "esxi_host": esxi_host,
            }

            ip_map = guest_ips_by_mac(vm)
            devices = vm.config.hardware.device if vm.config else []
            nics = [
                d for d in devices if isinstance(d, vim.vm.device.VirtualEthernetCard)
            ]

            if not nics:
                writer.writerow({**{f: "" for f in FIELDS}, **base})
                continue

            for nic in nics:
                network, net_type, switch, port_key, pg_key = describe_backing(
                    nic, dvpg_map, std_pg_map, esxi_host
                )
                mac = nic.macAddress or ""
                row = {f: "" for f in FIELDS}
                row.update(base)
                row.update(
                    {
                        "nic_label": nic.deviceInfo.label if nic.deviceInfo else "",
                        "adapter_type": type(nic).__name__.rsplit(".", 1)[-1],
                        "mac_address": mac,
                        "connected": nic.connectable.connected
                        if nic.connectable
                        else "",
                        "network": network,
                        "network_type": net_type,
                        "switch": switch,
                        "port_key": port_key,
                        "portgroup_key": pg_key,
                        "ip_addresses": ip_map.get(mac.lower(), ""),
                    }
                )
                writer.writerow(row)
    finally:
        Disconnect(si)


if __name__ == "__main__":
    main()
