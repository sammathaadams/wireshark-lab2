# Wireshark Network Analysis Lab 2 — Packet Capture & Protocol Inspection

## Overview

This lab demonstrates hands-on network traffic analysis using Wireshark, the industry-standard open-source packet capture tool. It covers live traffic capture, display filter construction, DNS query/response inspection, TCP three-way handshake observation, cleartext credential exposure over HTTP, and full TCP stream reconstruction — reflecting real-world workflows used by SOC analysts, network engineers, and incident responders.

**Tool:** Wireshark (free, open source — no account or licence required)  
**Platform:** Microsoft Azure — Windows Server 2025 VM provisioned via Azure CLI  
**Automation:** PowerShell (`Start-HttpTestServer.ps1`, `Invoke-TsharkCapture.ps1`)  
**Certification Alignment:** CompTIA Network+ · Security+ · CySA+

---

## Business Context

Every network event — a failed login, a slow service, a suspicious connection — leaves a trace in the underlying packet stream. Organizations use packet capture as the definitive diagnostic tool when logs are ambiguous or incomplete. Wireshark allows engineers to inspect traffic at every layer of the protocol stack, from the Ethernet frame to the application payload.

This lab simulates four scenarios that appear regularly in enterprise environments: resolving DNS failures by tracing query/response pairs; diagnosing broken connections by spotting incomplete TCP handshakes; identifying insecure applications that expose credentials in cleartext HTTP; and reconstructing the complete conversation between two hosts during an incident investigation.

The analytical skills built here transfer directly to cloud-native tooling — Azure Network Watcher, VPC Flow Logs, and Microsoft Sentinel all surface the same protocol-layer patterns that Wireshark makes visible at the packet level.

---

## Prerequisites

- Azure subscription with permissions to create Resource Groups, VMs, VNets, and NSGs
- Azure CLI installed locally (`az --version` to verify)
- Windows Remote Desktop client
- PowerShell 5.1+ (available on Windows Server 2025 by default)
- Basic familiarity with IP networking concepts (IP addresses, ports, protocols)

---

## Architecture

![Lab 2 Azure Architecture — ws01 Wireshark Analysis Station](screenshots/architecture.svg)

| Resource | Name | Type |
|---|---|---|
| Resource Group | `rg-lab02-0626` | Azure Resource Group |
| Virtual Machine | `ws01` | `Microsoft.Compute/virtualMachine` |
| Virtual Network | `ws01-vnet` | Azure VNet |
| Network Security Group | `ws01-nsg` | Azure NSG |

---

## Steps

### 1. Initialize the Project Repository

Create the local project directory, initialize Git, and scaffold the folder structure.

```powershell
mkdir wireshark-lab2
cd wireshark-lab2
git init
echo "# Wireshark Network Analysis Lab" > README.md
mkdir scripts screenshots
```

---

### 2. Deploy the Azure Virtual Machine

Provision a Windows Server 2025 VM to Azure using the Azure CLI. The deployment creates the VM, a VNet, and an NSG in a single operation under resource group `rg-lab02-0626`.

- **VM Name:** `ws01`
- **Subscription:** Azure subscription 1
- **Resource Group:** `rg-lab02-0626`
- **Image:** Windows Server 2025 Datacenter
- **Size:** Standard_D2s_v3

```powershell
# Create the resource group
az group create --name rg-lab02-0626 --location westus2

# Deploy the Windows Server 2025 VM
az vm create `
  --resource-group rg-lab02-0626 `
  --name ws01 `
  --image MicrosoftWindowsServer:WindowsServer:2025-datacenter-g2:latest `
  --admin-username azureuser `
  --admin-password 'YourStrongPassword123!' `
  --public-ip-sku Standard `
  --size Standard_D2s_v3

# Open RDP port 3389
az vm open-port --resource-group rg-lab02-0626 --name ws01 --port 3389

# Note: the public IP is printed in the JSON output when az vm create completes.
# Copy the value of "publicIpAddress" from that output — you will need it for RDP.
```

![Azure CLI — az vm create complete, publicIpAddress visible in JSON output](screenshots/azure-cli-vm-deploy.png)

---

### 3. Connect via Remote Desktop (RDP)

Once the VM is running, retrieve its public IP from the Azure CLI output above and connect using Remote Desktop.

- Authenticate with the `azureuser` credentials set during VM creation.

```bash
# Confirm VM is running before connecting
az vm show --resource-group rg-lab02-0626 --name ws01 --query "powerState" -d -o tsv
```

![RDP connection to ws01](screenshots/rdp-connection-ws01.png)

---

### 4. Install Wireshark on the VM

From inside the RDP session, open **PowerShell as Administrator** on `ws01` and install Wireshark using the official installer:

```powershell
# Download the Wireshark installer — Npcap is bundled and installs in the same wizard
Invoke-WebRequest -Uri "https://2.na.dl.wireshark.org/win64/Wireshark-latest-x64.exe" -OutFile "$env:TEMP\wireshark-installer.exe"
Start-Process -FilePath "$env:TEMP\wireshark-installer.exe" -Wait

# Verify installation
& "C:\Program Files\Wireshark\tshark.exe" --version
```

Accept all defaults in the installer wizard — Npcap is a checked component and installs automatically in the same wizard. No separate download or installer required.

![Wireshark 4.6.6 setup wizard completing on ws01 via Invoke-WebRequest](screenshots/wireshark-install-verify.png)

---

### 5. The Wireshark Interface — Orientation

Open Wireshark. Before starting any exercise, familiarise yourself with the four main areas:

| Area | Description |
|---|---|
| **Welcome Screen** | Lists all available network interfaces with live wave graphs. Double-click the active interface (highest wave graph activity) to begin a capture. |
| **Packet List Pane** | Top panel during a capture — one row per packet. Columns show packet number, timestamp, source/destination IP, protocol, length, and an Info summary. |
| **Packet Detail Pane** | Middle panel — click any packet to see the full decoded protocol stack (Ethernet → IP → TCP/UDP → application payload). Expand any layer to inspect individual fields. |
| **Filter Bar** | Input bar above the packet list. Type a display filter and press **Enter** to narrow the visible packets without discarding the capture. |

> **Display vs Capture filters:** Display filters are applied *after* capture — they hide packets without discarding them. Always use display filters in this lab so you can re-examine the same capture through multiple lenses.

---

### 6. Apply Display Filters

Type a filter into the filter bar at the top of the Wireshark window and press **Enter**. The packet list updates instantly.

| Filter | What It Shows |
|---|---|
| `dns` | All DNS queries and responses |
| `http` | Unencrypted HTTP traffic only |
| `tcp` | All TCP traffic |
| `tcp.flags.syn == 1` | TCP SYN packets — connection attempts |
| `tcp.flags.reset == 1` | TCP RST packets — refused/closed connections |
| `icmp` | All ICMP including ping |
| `ip.addr == 192.168.1.1` | All traffic to or from a specific IP |
| `http.request.method == POST` | HTTP POST requests (login form submissions) |

---

### 7. Exercise A — Capture a DNS Lookup

Start a capture, run `nslookup google.com` from a separate terminal window, stop the capture, and apply the `dns` filter.
```cmd
nslookup google.com
```

In the packet list, find:
- **Query:** Info column shows `Standard query A google.com`
- **Response:** Info column shows `Standard query response A google.com`

Click the response packet → expand **Domain Name System (response)** → expand **Answers** → confirm the A record IP matches the nslookup terminal output.

![DNS filter applied — Standard query response packets visible, A record IP matches nslookup output](screenshots/dns-response-answers.png)

> **Why this matters in production:** Unexpected DNS queries to unknown domains are one of the earliest indicators of malware phoning home to a command-and-control server. SOC analysts apply the `dns` filter as a first step in any suspicious-host investigation.

---

### 8. Exercise B — Watch the TCP Three-Way Handshake

Start a capture, navigate to `http://neverssl.com`, stop the capture, get the IP with `nslookup neverssl.com`, then apply:

```
tcp and ip.addr == <IP from nslookup>
```

Find the three-packet handshake:

| Packet | Flags | Meaning |
|---|---|---|
| 1st | `SYN` | Your machine: "I want to connect. Here is my sequence number." |
| 2nd | `SYN, ACK` | Server: "I got your request. Here is my sequence number. Accepted." |
| 3rd | `ACK` | Your machine: "Got it. Connection is open. Ready to send data." |

> **Diagnostic patterns:** SYN with no SYN-ACK = server unreachable or port blocked. RST packet = connection forcibly terminated. These two patterns are the primary signals when diagnosing connectivity failures.

![TCP three-way handshake — SYN → SYN-ACK → ACK sequence with ECN flags visible](screenshots/tcp-handshake.png)

---

### 9. Exercise C — Spot Cleartext Credentials (HTTP)

> **Educational use only.** Only capture on networks and systems you own or have explicit permission to test.

In Wireshark, start a capture on your **active Ethernet interface**. Open a browser and navigate to:

```
http://zero.webappsecurity.com/login.html
```

This is a deliberately vulnerable test banking application maintained for security education — it runs over HTTP with no TLS. Enter any test credentials and click **Sign in**, stop the capture, and apply:

![Zero Bank login form — credentials entered before submitting](screenshots/zero-bank-login-form.png)

```
http.request.method == POST and http.host contains "zero"
```

> **Note:** Azure VMs generate background HTTP traffic to `168.63.129.16` (Azure's internal health service). The host filter above excludes that noise and isolates only the login POST.

Click the POST packet → expand **Hypertext Transfer Protocol** → expand **HTML Form URL Encoded** → username and password are visible in plaintext.

![HTTP POST packet — HTML Form URL Encoded section showing plaintext username and password](screenshots/http-cleartext-credentials.png)

> **Why this matters:** Without TLS encryption, anyone on the network path — an ISP, a coffee shop router, a man-in-the-middle attacker — can read credentials exactly as typed. This demonstration is how security teams prove the vulnerability to developers who resist adopting HTTPS.

---

### 10. Exercise D — Follow a Full TCP Stream

Capture any HTTP traffic, right-click an HTTP packet, and select **Follow → TCP Stream**.

Wireshark reassembles the complete conversation:
- **Red text** — your browser's outbound HTTP request (headers, method, path)
- **Blue text** — the server's inbound response (status code, headers, HTML body)

![TCP stream view — full HTTP request (red) and response (blue) reconstructed](screenshots/tcp-stream-follow.png)

> **Incident response application:** Individual packets are fragments — the stream view shows the complete conversation. Incident responders use this to reconstruct exactly what data was transferred and what commands were issued during a network event.

---

### 11. Save and Export Captures

```
# Save full capture
File → Save As → dns-lookup-google.pcapng

# Export only filtered packets
Apply display filter → File → Export Specified Packets → Displayed

# Automate capture via tshark (terminal)
.\scripts\Invoke-TsharkCapture.ps1 -Interface "Wi-Fi" -OutputFile "capture.pcapng" -DurationSec 30
```

---

### 12. Commit and Push to GitHub

```bash
git add .
git commit -m "feat: wireshark lab2 — dns, tcp handshake, cleartext creds, stream analysis"
git push
```

---

## Key Skills Demonstrated

- Azure CLI VM provisioning — resource group, VM, VNet, NSG, and RDP port configuration
- Windows Server 2025 VM deployment and Remote Desktop access
- Wireshark installation via PowerShell on a cloud-hosted Azure VM
- Live packet capture on active network interfaces
- Display filter construction for DNS, TCP, HTTP, and IP-specific traffic isolation
- DNS query and response packet analysis including A record inspection
- TCP three-way handshake identification and connectivity diagnosis
- Cleartext credential exposure demonstration via HTTP POST capture
- TCP stream reconstruction for full client/server conversation review
- tshark CLI automation for scriptable and headless packet capture
- `.pcapng` file management and Git version control for network analysis artefacts

---

## Cleanup

To avoid ongoing Azure charges, deallocate or delete the `ws01` VM and all associated resources from the `rg-lab02-0626` resource group when the lab is complete.

```bash
az group delete --name rg-lab02-0626 --yes --no-wait
```
