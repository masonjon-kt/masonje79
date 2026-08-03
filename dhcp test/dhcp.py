from scapy.all import Ether, IP, UDP, BOOTP, DHCP, srp1

def request_dhcp_options(interface):
    # Create a MAC address for the client (using all Fs for a broadcast discover)
    client_mac = "aa:bb:cc:dd:ee:ff"
    
    # 1. Craft the DHCP Discover packet
    # UDP ports 68 (client) and 67 (server) are the standard ports for DHCP
    discover_packet = (
        Ether(dst="ff:ff:ff:ff:ff:ff") /
        IP(src="0.0.0.0", dst="255.255.255.255") /
        UDP(sport=68, dport=67) /
        BOOTP(chaddr=client_mac, xid=0x10203040) /
        DHCP(options=[("message-type", "discover"), "end"])
    )

    print("Sending DHCP Discover...")
    
    # 2. Send the packet and wait for the first DHCP Offer
    try:
        response = srp1(discover_packet, iface=interface, timeout=5, verbose=False)
    except Exception as e:
        print(f"Error sending/receiving: {e}")
        return

    if response:
        print("DHCP Server Responded!\n")
        # 3. Parse the DHCP options
        if DHCP in response:
            dhcp_options = response[DHCP].options
            
            # Print all raw options
            print("--- All DHCP Options ---")
            for option in dhcp_options:
                print(option)
            
            # Or extract specific ones by name if needed
            # e.g., print(dict(dhcp_options).get('name_server'))
    else:
        print("No response received from any DHCP server.")

# Replace 'eth0' with your actual network interface name
request_dhcp_options(interface="wlp0s20f3")
