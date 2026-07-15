#!/bin/bash

set -e

#############################################
# Verify script is run with sudo/root
#############################################
if [ "$EUID" -ne 0 ]; then
    echo "Please run using:"
    echo "sudo ./install-kubernetes.sh"
    exit 1
fi

#############################################
# Detect Original User
#############################################
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo "~$REAL_USER")

echo "=============================================="
echo " Kubernetes Automatic Installation"
echo "=============================================="
echo "Detected User : $REAL_USER"
echo "Detected Home : $REAL_HOME"
echo ""

#############################################
# 1. Update Ubuntu
#############################################
echo "[1/10] Updating Ubuntu..."

apt update
apt upgrade -y

#############################################
# 2. Disable Swap
#############################################
echo "[2/10] Disabling Swap..."

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

#############################################
# 3. Configure Kernel
#############################################
echo "[3/10] Configuring Kernel..."

cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF

sysctl --system

#############################################
# 4. Install containerd
#############################################
echo "[4/10] Installing containerd..."

apt install -y containerd

mkdir -p /etc/containerd

containerd config default >/etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
/etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

#############################################
# 5. Install Kubernetes
#############################################
echo "[5/10] Installing Kubernetes..."

apt install -y apt-transport-https ca-certificates curl gpg

mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" \
>/etc/apt/sources.list.d/kubernetes.list

apt update

apt install -y kubelet kubeadm kubectl

apt-mark hold kubelet kubeadm kubectl

#############################################
# 6. Detect IP
#############################################
echo "[6/10] Detecting Private IP..."

IP=$(hostname -I | awk '{print $1}')

echo "Private IP : $IP"

#############################################
# 7. Initialize Cluster
#############################################
echo "[7/10] Initializing Kubernetes..."

kubeadm init \
--apiserver-advertise-address="$IP" \
--pod-network-cidr=192.168.0.0/16

#############################################
# 8. Configure kubectl
#############################################
echo "[8/10] Configuring kubectl..."

mkdir -p "$REAL_HOME/.kube"

cp /etc/kubernetes/admin.conf "$REAL_HOME/.kube/config"

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.kube"

export KUBECONFIG="$REAL_HOME/.kube/config"

#############################################
# Wait until API Server responds
#############################################
echo "Waiting for API Server..."

until kubectl --kubeconfig="$REAL_HOME/.kube/config" get nodes >/dev/null 2>&1
do
    sleep 5
done

#############################################
# 9. Install Calico
#############################################
echo "[9/10] Installing Calico..."

kubectl --kubeconfig="$REAL_HOME/.kube/config" apply \
-f https://raw.githubusercontent.com/projectcalico/calico/v3.30.4/manifests/calico.yaml

echo "Waiting 60 seconds for cluster..."

sleep 60

#############################################
# 10. Verify Cluster
#############################################
echo "[10/10] Cluster Information"

kubectl --kubeconfig="$REAL_HOME/.kube/config" get nodes -o wide

echo ""

kubectl --kubeconfig="$REAL_HOME/.kube/config" get pods -A

echo ""

kubectl --kubeconfig="$REAL_HOME/.kube/config" cluster-info

echo ""
echo "=============================================="
echo " Kubernetes Installation Completed Successfully"
echo "=============================================="
echo ""
echo "Now simply run:"
echo ""
echo "kubectl get nodes"
echo "kubectl get pods -A"
echo "kubectl cluster-info"
echo ""
