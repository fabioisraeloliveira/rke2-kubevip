#!/bin/bash
# ┌────────────────────────────────────────────────────────────┐
# │ RKE2 High Availability Cluster Setup with Kube-VIP         │
# │                                                            │
# │ Author: Fábio Israel                                       │
# │ Description:                                               │
# │   Automates the deployment of a 3-node RKE2 HA cluster     │
# │   using Kube-VIP for control-plane VIP management.         │
# │   Designed for on-premise environments (e.g., vSphere).    │
# │                                                            │
# │ Version: 1.0                                               │
# │ License: MIT                                               │
# └────────────────────────────────────────────────────────────┘
#

set -e

# --- CONFIGURAÇÃO ---
VIP="<ip vip>"
MASTER1_IP="<ip master1>"
MASTER2_IP="<ip master2>"
MASTER3_IP="<ip master2>"
INTERFACE="ens192"
POD_CIDR="198.18.0.0/16"
SERVICE_CIDR="198.19.0.0/16"
RKE2_TOKEN="your-token"
IMAGEKUBEVIP="ghcr.io/kube-vip/kube-vip:v0.9.2"
ALL_MASTER_IPS=("${MASTER1_IP}" "${MASTER2_IP}" "${MASTER3_IP}")
RKE2_DATA_DIR="/var/lib/rancher/rke2"
# --- FIM DA CONFIGURAÇÃO ---

create_audit_manifest() {
    echo "=> create audit-policy manifest..."
    sudo tee "/etc/rancher/rke2/audit-policy.yaml" <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - "RequestReceived"
rules:
  - level: RequestResponse
    resources:
    - group: "" # core
      resources: ["secrets", "configmaps"]
    - group: "authentication.k8s.io"
      resources: ["tokenreviews"]
    verbs: ["create", "update", "patch", "delete"]
  - level: Metadata
    verbs: ["create", "update", "delete", "patch"]
    resources:
    - group: "*"
      resources: ["*"]
EOF
}

create_psa_manifest() {
    echo "=> Create PSA manifest..."
    sudo tee "/etc/rancher/rke2/rke2-pss.yaml" <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "restricted"
        enforce-version: "latest"
        audit: "restricted"
        audit-version: "latest"
        warn: "restricted"
        warn-version: "latest"
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces: [calico-apiserver,
                     calico-system,
                     cattle-alerting,
                     cattle-csp-adapter-system,
                     cattle-elemental-system,
                     cattle-epinio-system,
                     cattle-externalip-system,
                     cattle-fleet-local-system,
                     cattle-fleet-system,
                     cattle-gatekeeper-system,
                     cattle-global-data,
                     cattle-global-nt,
                     cattle-impersonation-system,
                     cattle-istio,
                     cattle-istio-system,
                     cattle-logging,
                     cattle-logging-system,
                     cattle-monitoring-system,
                     cattle-neuvector-system,
                     cattle-prometheus,
                     cattle-provisioning-capi-system,
                     cattle-resources-system,
                     cattle-sriov-system,
                     cattle-system,
                     cattle-ui-plugin-system,
                     cattle-windows-gmsa-system,
                     cert-manager,
                     cis-operator-system,
                     fleet-default,
                     ingress-nginx,
                     istio-system,
                     kube-node-lease,
                     kube-public,
                     kube-system,
                     longhorn-system,
                     rancher-alerting-drivers,
                     security-scan,
                     tigera-operator,
                     system-upgrade-controller,
                     system-upgrade]
EOF
}

create_kube_vip_manifest() {
    sudo mkdir -p "${RKE2_DATA_DIR}/agent/pod-manifests"
    echo "=> Create Kube-VIP manifest..."
    sudo tee "${RKE2_DATA_DIR}/agent/pod-manifests/kube-vip.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
    operator: Exists
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
    operator: Exists
  hostAliases:
  - ip: "127.0.0.1"
    hostnames:
    - "kubernetes"
  containers:
  - name: kube-vip
    image: ${IMAGEKUBEVIP}
    imagePullPolicy: IfNotPresent
    args:
    - manager
    - --interface=${INTERFACE}
    - --address=${VIP}
    - --port=6443
    - --vipSubnet=32 # Parâmetro correto para v0.9.2
    - --arp
    - --controlplane
    - --leaderElection
    - --namespace=kube-system
    - --prometheusHTTPServer=0.0.0.0:2113
    livenessProbe:
      httpGet:
        path: /metrics
        port: 2113
      initialDelaySeconds: 15
      periodSeconds: 20
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
        - SYS_TIME
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/rancher/rke2/rke2.yaml
    name: kubeconfig
EOF
}

CURRENT_IP=$(hostname -I | awk '{print $1}')
CONFIG_FILE_PATH="/etc/rancher/rke2/config.yaml"

# Function config.yaml
create_rke2_config() {
    sudo tee "$1" <<EOF
token: "${RKE2_TOKEN}"
tls-san:
  - "${VIP}"
$(for ip in "${ALL_MASTER_IPS[@]}"; do echo "  - \"${ip}\""; done)
cni: "calico"
cluster-cidr: "${POD_CIDR}"
service-cidr: "${SERVICE_CIDR}"
etcd-expose-metrics: true
write-kubeconfig-mode: "0600"
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 5
secrets-encryption: true
protect-kernel-defaults: true
profile: cis
pod-security-admission-config-file: /etc/rancher/rke2/rke2-pss.yaml
#kube-apiserver-arg:
#  - "audit-policy-file=/etc/rancher/rke2/audit-policy.yaml"
#  - "audit-log-path=/var/lib/rancher/rke2/server/logs/audit.log"
#  - "audit-log-maxage=30"
#  - "audit-log-maxbackup=10"
#  - "audit-log-maxsize=100"
disable:
  - rke2-ingress-nginx
EOF
}

# --- estrutura ---
sudo mkdir -p /etc/rancher/rke2
sudo mkdir -p ${RKE2_DATA_DIR}/server/logs
#create_audit_manifest
create_psa_manifest
create_kube_vip_manifest

if [ "$CURRENT_IP" == "$MASTER1_IP" ]; then
    echo "### DETECTED: First Master ($CURRENT_IP) ###"
    create_rke2_config ${CONFIG_FILE_PATH}
else
    echo "### DETECTED: Node join ($CURRENT_IP) ###"
    create_rke2_config ${CONFIG_FILE_PATH}
    echo "server: https://${MASTER1_IP}:9345" | sudo tee -a ${CONFIG_FILE_PATH}
fi

curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="server" sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

echo "Node setup completed! The RKE2 service is starting."
