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

Optional: Rancher UI Installation

Step 1: Deploy Kube-VIP via Helm
<pre>
helm repo add kube-vip https://kube-vip.github.io/helm-charts
helm repo update
</pre>
Create a kubevip-values.yaml file:
<pre>
config:
  address: "reserved-ip"

loadBalancer:
  enabled: true

addressPool:
  name: default
  addresses:
    - reserved-ip/32
</pre>

Install Kube-VIP:
<pre>
helm upgrade --install kube-vip kube-vip/kube-vip \
  --version 0.6.6 \
  --namespace kube-system \
  -f kubevip-values.yaml
</pre>
Step 2: Deploy ingress-nginx
<pre>
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
</pre>

Create an ingress-nginx-values.yaml file:
<pre>
controller:
  service:
    enabled: true
    type: LoadBalancer
    loadBalancerIP: reserved-ip
  publishService:
    enabled: true
</pre>

Install ingress-nginx:
<pre>
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f ingress-nginx-values.yaml

kubectl get svc -n ingress-nginx
</pre>

Step 3: Generate a Valid TLS Certificate
<pre>
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout tls.key \
  -out tls.crt \
  -subj "/C=BR/ST=<state>/L=<city>/O=<org>/CN=<dns>" \
  -addext "subjectAltName = DNS:dns"
</pre>

Create secrets for Rancher:
<pre>
kubectl create namespace cattle-system

kubectl -n cattle-system create secret tls tls-rancher-ingress \
  --cert=tls.crt \
  --key=tls.key

cp tls.crt cacerts.pem

kubectl -n cattle-system create secret generic tls-ca \
  --from-file=cacerts.pem
</pre>

Step 4: Install Rancher with Helm
<pre>
helm repo add rancher-stable https://releases.rancher.com/server-charts/latest
helm repo update

helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=<DNS> \
  --set bootstrapPassword=<your_pass> \
  --set replicas=3 \
  --set ingress.ingressClassName=nginx \
  --set ingress.tls.source=secret \
  --set ingress.tls.secretName=tls-rancher-ingress \
  --set global.cattle.psp.enabled=false \
  --set privateCA=true
</pre>
Monitor deployment:
<pre>
kubectl rollout status deploy/rancher -n cattle-system
journalctl -u rancher-system-agent -f
</pre>


The script will detect whether the node is the first master and apply the correct configuration automatically.

Contributing
Pull requests are welcome! For major changes, please open an issue first to discuss what you’d like to modify.
