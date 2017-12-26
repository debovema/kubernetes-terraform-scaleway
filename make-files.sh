#!/usr/bin/env bash

. ./ips.txt
cat > scw-install.sh << FIN
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

echo "DOCKER_OPTS='-H unix:///var/run/docker.sock --storage-driver aufs --label provider=scaleway --mtu=1500 --insecure-registry=10.0.0.0/8'" > /etc/default/docker
systemctl restart docker

apt-get update -qq \
 && apt-get install -y -q --no-install-recommends zsh kubelet kubeadm kubectl kubernetes-cni \
 && apt-get clean

echo "Kubernetes token is \$KUBERNETES_TOKEN"

for arg in "\$@"
do
  case \$arg in
    'master')
      SUID=\$(scw-metadata --cached ID)
      PUBLIC_IP=\$(scw-metadata --cached PUBLIC_IP_ADDRESS)
      PRIVATE_IP=\$(scw-metadata --cached PRIVATE_IP)

      kubeadm --token=\$KUBERNETES_TOKEN --apiserver-advertise-address=\$PUBLIC_IP --service-dns-domain=\$SUID.pub.cloud.scaleway.com --pod-network-cidr=192.168.0.0/16 init
      export KUBECONFIG=/etc/kubernetes/admin.conf
      KUBECONFIG=/etc/kubernetes/admin.conf kubectl create -f https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/hosted/kubeadm/1.7/calico.yaml

      mkdir -p /tmp/certs
      cd /tmp/certs
      openssl genrsa -des3 -passout pass:x -out dashboard.pass.key 2048
      openssl rsa -passin pass:x -in dashboard.pass.key -out dashboard.key
      rm dashboard.pass.key
      openssl req -new -key dashboard.key -out dashboard.csr -subj '/CN=www.mydom.com/O=My Company Name LTD./C=US'
      openssl x509 -req -sha256 -days 365 -in dashboard.csr -signkey dashboard.key -out dashboard.crt
      kubectl create secret generic kubernetes-dashboard-certs --from-file=/tmp/certs -n kube-system
      KUBECONFIG=/etc/kubernetes/admin.conf kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
      break
      ;;
    'slave')
      kubeadm join --discovery-token-unsafe-skip-ca-verification --token \$KUBERNETES_TOKEN $MASTER_00:6443
      break
      ;;
 esac
done

# Install Oh My ZSH
curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh > /tmp/ohmyz.sh && sed -i 's|env zsh|#env zsh|' /tmp/ohmyz.sh && sed -i 's|git clone|git clone -q|' /tmp/ohmyz.sh && chmod u+x /tmp/ohmyz.sh && . /tmp/ohmyz.sh && sed -ie 's|ZSH_THEME=".*"|ZSH_THEME="ys"|' ~/.zshrc

echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.zshrc
FIN
rm -rf ./ips.txt
