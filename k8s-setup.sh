#!/bin/bash

export CRIO=1
# add useful tools - mainly curl we need to get metadata
apt update
apt install -y curl wget openssl bash-completion

export METADATA_URL=http://metadata.google.internal/computeMetadata/v1/instance/attributes

CRIO=$(curl $METADATA_URL/CRIO -H "Metadata-Flavor: Google")
CRIO_DISTRO_REPO=$(curl $METADATA_URL/CRIO_DISTRO_REPO -H "Metadata-Flavor: Google")
CRIO_DISTRO_K8S_VER=$(curl $METADATA_URL/CRIO_DISTRO_K8S_VER -H "Metadata-Flavor: Google")

NODE_IS_CP_MASTER=$(curl $METADATA_URL/NODE_IS_CP_MASTER -H "Metadata-Flavor: Google")
CA_PUBKEY_DIGEST=$(curl $METADATA_URL/ca_pubkey_digest -H "Metadata-Flavor: Google")
K8S_CP_TOKEN=$(curl $METADATA_URL/k8s_cp_token -H "Metadata-Flavor: Google")

# add kubernetes repo
echo "deb  http://apt.kubernetes.io/  kubernetes-xenial  main" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list
# add repo-signing-key
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo apt-key add -

# update system
sudo apt update

if [ -z "$CRIO_DISTRO_REPO" ]
then
   CRIO_DISTRO_REPO=Debian_11
fi


if [ -z "$CRIO_DISTRO_K8S_VER" ]
then
   CRIO_DISTRO_K8S_VER=1.21
fi

echo CRIO=$CRIO >> /setupvars
echo CRIO_DISTRO_K8S_VER=$CRIO_DISTRO_K8S_VER >> /setupvars
echo CRIO_DISTRO_REPO=$CRIO_DISTRO_REPO >> /setupvars

# install kubernetes stuff and pin
apt install -y \
	kubeadm=1.21.1-00 \
	kubelet=1.21.1-00 \
	kubectl=1.21.1-00

apt-mark hold kubelet kubeadm kubectl
echo "source <(kubectl completion bash)" >> $HOME/.bashrc

# CRI-O stuff
if [ $CRIO ];
then
    modprobe overlay
    modprobe br_netfilter

    cat << __EOF__ > /etc/sysctl.d/99-kubernetes-cri.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.ipv4.ip_forward                 = 1
    net.bridge.bridge-nf-call-ip6tables = 1
__EOF__

    sysctl --system
    # export OS=xUbuntu_20.04
    # export VER=1.21

    # Add CRI-O Repos
    echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_DISTRO_K8S_VER/$CRIO_DISTRO_REPO/ /" \
	| tee -a /etc/apt/sources.list.d/cri-0.list
    echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$CRIO_DISTRO_REPO/ /" \
	| tee -a /etc/apt/sources.list.d/libcontainers.list
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$CRIO_DISTRO_REPO/Release.key \
	| apt-key add -
    curl -L http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_DISTRO_K8S_VER/$CRIO_DISTRO_REPO/Release.key \
	| apt-key add -

    apt update
    apt install -y cri-o cri-o-runc
    systemctl daemon-reload
    systemctl enable crio
    systemctl start crio
fi

# Only on control plane
if [ "$NODE_IS_CP_MASTER" = "1" ];
then
    mkdir -p  /etc/kubernetes/pki
    curl $METADATA_URL/ca_cert \
	 -H "Metadata-Flavor: Google" \
	 -o /etc/kubernetes/pki/ca.crt
    curl $METADATA_URL/ca_key \
	 -H "Metadata-Flavor: Google" \
	 -o /etc/kubernetes/pki/ca.key

    # Issue certificate also for external IP to reach cluster from outside
    MY_EXTERNAL_IP=$(curl \
	"http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" \
	 -H "Metadata-Flavor: Google")

    # 
    #  --pod-network-cidr string
    #  --service-cidr 
    kubeadm init\
	    --upload-certs \
	    --apiserver-cert-extra-sans $MY_EXTERNAL_IP \
	    --control-plane-endpoint $(hostname) \
	    --token $K8S_CP_TOKEN  \
	| tee /kubeadm-init.out

    curl $METADATA_URL/cni_deploy \
	 -H "Metadata-Flavor: Google" \
	 -o /tmp/cni.yaml
    kubectl apply -n kube-system -f /tmp/cni.yaml
    
else # Worker nodes

    # DNS name for control plane master - reachable from node
    K8S_CP_MASTER_NAME=$(curl $METADATA_URL/k8s_cp_master -H "Metadata-Flavor: Google")

    # join cluster
    kubeadm join \
	    $K8S_CP_MASTER_NAME:6443 \
	    --token $K8S_CP_TOKEN \
            --discovery-token-ca-cert-hash sha256:$CA_PUBKEY_DIGEST \
	| tee /kubeadm-init.out
fi
