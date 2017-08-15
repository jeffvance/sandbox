#! /bin/bash

LOG_FILE=/root/start-script.log
SUCCESS_FILE=/root/__STARTUP_SUCCESS

if [ $(id -u) != 0  ]; then
	echo "!!! Must run as sudo  !!!"
	sudo su
fi

set -x
set -e
set -o pipefail

exec 3>&1 4>&2
trap $(exec 1>&3 2>&4) 0 1 2 3
exec 1>${LOG_FILE} 2>&1

echo "============================================="
echo "               Start-Up Script"
echo "============================================="

systemctl stop firewalld && systemctl disable firewalld

# Docker
echo "============= Installing Docker ============="
yum install docker-1.12.6 -y -q -e 0
systemctl enable docker
systemctl start docker

# Kubectl
echo "============= Installing kubectl ============"
mkdir -p /root
cd /root/
curl -sSLO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/bin/

# Kubeadm
echo "============== Installing kubeadm  =========="
su -c "cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF"
setenforce 0
yum install kubelet kubeadm -y -q -e 0
systemctl enable kubelet
systemctl start kubelet


if [[ $(hostname -s) = *"master"* ]]; then
	echo "Looks like this is a master node.  Doing kubeadm init"
	# QoL Setup
	yum install bash-completion tmux -y
	mkdir -p /root/.kube
	kubectl completion bash > /root/.kube/completion
	echo "source /root/.kube/completion" >> /root/.bashrc

	# Heketi
	echo "============== Installing kubeadm  =========="
	curl -sSL https://github.com/heketi/heketi/releases/download/v4.0.0/heketi-client-v4.0.0.linux.amd64.tar.gz | tar -xz
	mv $(find ./ -name heketi-cli) /usr/bin/
	
	# Gluster-Kubernetes
	curl -sSL https://github.com/gluster/gluster-kubernetes/archive/master.tar.gz | tar -xz

	# Kubeadm
	kubeadm init --pod-network-cidr=10.244.0.0/16 
	mkdir -p /root/.kube
	sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
	sudo chown $(id -u):$(id -g) /root/.kube/config
	kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
	kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel-rbac.yml
fi

touch $SUCCESS_FILE
