# RKE2 HA Cluster with Kube-VIP Using Bash — On-Premise Automation

This project provides a Bash script to deploy a Highly Available (HA) Kubernetes cluster using RKE2 and Kube-VIP in an on-premise environment (e.g., vSphere).
No need for cloud providers, HAProxy, Keepalived, or complex tooling. Just pure Bash logic, clean automation, and simple infrastructure.

## What the Script Does

- Creates a 3-node RKE2 HA cluster
- Uses Kube-VIP v0.9.2 to manage the control-plane VIP address
- Automatically detects the node role based on IP address
- Generates Kubernetes manifests:
  - Kube-VIP Pod (with ARP and leader election)
  - Pod Security Admission (PSA) configuration
- Builds the `config.yaml` file with:
  - VIP via `tls-san`
  - Custom network CIDRs (Calico CNI)
  - CIS security profile
  - etcd snapshots and encryption
- Starts the `rke2-server` service on each node

## Requirements

- Linux (Ubuntu, CentOS, or compatible)
- Static IPs for all master nodes
- Root access
- Network interface name (e.g., `ens192`)
- RKE2 token (shared across nodes)
- Internet access to pull Kube-VIP image from GitHub Container Registry

## Usage

1. Clone the repository:
   git clone https://github.com/fabioisraeloliveira/rke2-kubevip.git
   cd rke2-kubevip

2. Edit the variables at the top of rke2masters.sh: <br>
VIP="<your-vip>" <br>
MASTER1_IP="<master1-ip>" <br>
MASTER2_IP="<master2-ip>" <br>
MASTER3_IP="<master3-ip>" <br>
INTERFACE="ens192" <br>
RKE2_TOKEN="your-token"

3. Run the script on each master node: <br>
chmod +x rke2masters.sh <br>
./rke2masters.sh

The script will detect whether the node is the first master and apply the correct configuration automatically.

Contributing
Pull requests are welcome! For major changes, please open an issue first to discuss what you’d like to modify.
