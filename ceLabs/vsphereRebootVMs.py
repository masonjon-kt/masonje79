from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim
import ssl
import json
import requests

# Set your vSphere connection details here
VSPHERE_HOST = 'u060dvc11.kroger.com'
VSPHERE_USER = '<euid>@kroger.com'
VSPHERE_PASSWORD = '<pwd>'

PostUpdateURL = 'https://kproductivity.webhook.office.com/webhookb2/42affb90-f8e8-474a-a3f3-405201252dac@8331e14a-9134-4288-bf5a-5e2c8412f074/IncomingWebhook/d50e646c2656483982bfc46404443c95/be636d1f-2905-4507-a388-664f7ecf3202/V2miSnVPzEOW3WGJmruHDvrT6zpnB89jhdqHxiLvaOTTc1'
PostText = {
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "content": {
        "body": [
          {
            "type": "TextBlock",
            "size": "large",
            "weight": "bolder",
            "text": f"VM Check on {VSPHERE_HOST}"
          }
        ]
      }
    }
  ]
}

def add_entry_to_posttext(text):
    """Adds a new TextBlock entry to the PostText body."""
    print(f"- {text}")
    new_entry = {
        "type": "TextBlock",
        "text": text
    }
    PostText["attachments"][0]["content"]["body"].append(new_entry)


def get_all_vms(content):
    obj_view = content.viewManager.CreateContainerView(content.rootFolder, [vim.VirtualMachine], True)
    vms = obj_view.view
    vms = sorted(vms, key=lambda vm: vm.name.lower() if vm.name else "")
    obj_view.Destroy()
    return vms

def main():
    # Ignore SSL certificate verification
    context = ssl._create_unverified_context()

    si = SmartConnect(host=VSPHERE_HOST, user=VSPHERE_USER, pwd=VSPHERE_PASSWORD, sslContext=context)
    content = si.RetrieveContent()

    vms = get_all_vms(content)
    for vm in vms:
        if vm.runtime.powerState == vim.VirtualMachinePowerState.poweredOn:
            ip = vm.guest.ipAddress
            if not ip:
                add_entry_to_posttext(f"**Rebooting VM: {vm.name}**")
                try:
                    # Attempt graceful reboot via VMware Tools
                    vm.RebootGuest()
                except Exception as e:
                    add_entry_to_posttext(f"- Graceful reboot failed for {vm.name}: {e}. Attempting forced reset.")
                    try:
                        # Force reset (hard reboot) if VMware Tools is not available
                        task = vm.ResetVM_Task()
                        add_entry_to_posttext(f"- Forced reset initiated for {vm.name}.")
                    except Exception as ex:
                        add_entry_to_posttext(f"- Failed to force reset {vm.name}: {ex}")
            else:
                add_entry_to_posttext(f"VM {vm.name} has IP {ip}; skipping reboot.")
        elif vm.runtime.powerState == vim.VirtualMachinePowerState.poweredOff:
            add_entry_to_posttext(f"VM {vm.name} is powered off; skipping reboot.")

    # Post results to Teams
    headers = {'Content-Type': 'application/json'}
    response = requests.post(PostUpdateURL, headers=headers, data=json.dumps(PostText))
    if response.status_code != 200:
        print(f"Failed to post update: {response.status_code} {response.text}")
        

    Disconnect(si)

if __name__ == "__main__":
    main()