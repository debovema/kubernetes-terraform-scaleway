provider "scaleway" {
  organization = "${var.organization_key}"
  token = "${var.secret_key}"
  region = "${var.region}"
}

resource "scaleway_ip" "kubernetes_master" {
}

resource "scaleway_server" "kubernetes_master" {
  name = "${format("${var.kubernetes_cluster_name}-master-%02d", count.index)}"
  image = "${var.base_image_id}"
  public_ip = "${scaleway_ip.kubernetes_master.ip}"
  type = "${var.scaleway_master_type}"
  connection {
    user = "${var.user}"
    private_key = "${file(var.kubernetes_ssh_key_path)}"
  }

  provisioner "local-exec" {
    command = "rm -rf ./scw-install.sh ./scw-install-master.sh"
  }
  provisioner "local-exec" {
    command = "echo ${format("MASTER_%02d", count.index)}=\"${self.public_ip}\" >> ips.txt"
  }

  provisioner "local-exec" {
    command = "echo CLUSTER_NAME=\"${var.kubernetes_cluster_name}\" >> ips.txt"
  }
  provisioner "local-exec" {
    command = "./make-files.sh"
  }

  provisioner "local-exec" {
    command = "while [ ! -f ./scw-install.sh ]; do sleep 1; done"
  }

  provisioner "file" {
    source = "./scw-install.sh"
    destination = "/tmp/scw-install.sh"
  }

  provisioner "file" {
    source = "./traefik.yaml"
    destination = "/tmp/traefik.yaml"
  }

  provisioner "file" {
    source = "./kubernetes-dashboard-rbac.yaml"
    destination = "/tmp/kubernetes-dashboard-rbac.yaml"
  }

  provisioner "remote-exec" {
    inline = "sed -i 's|- .* # External IP|- ${self.public_ip} # External IP|' /tmp/traefik.yaml"
  }

  provisioner "remote-exec" {
    inline = "sed -i 's|host: \"traefik.$DOMAIN_NAME\"|host: \"traefik.${var.domain_name}\"|' /tmp/traefik.yaml"
  }

  provisioner "remote-exec" {
    inline = "sed -i 's|host: \"dashboard.$DOMAIN_NAME\"|host: \"dashboard.${var.domain_name}\"|' /tmp/traefik.yaml"
  }

  provisioner "remote-exec" {
    inline = <<EOT
      KUBERNETES_TOKEN="${var.kubernetes_token}" \
      KUBERNETES_DASHBOARD_USERNAME="${var.kubernetes_dashboard_username}" \
      KUBERNETES_DASHBOARD_PASSWORD="${var.kubernetes_dashboard_password}" \
      LE_MAIL="${var.le_email}" \
      LE_STAGING=${var.le_staging ? "--staging" : ""} \
      DOMAIN_NAME="${var.domain_name}" \
      bash /tmp/scw-install.sh master
EOT
  }

  provisioner "remote-exec" {
    inline = "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/traefik.yaml"
  }

  provisioner "remote-exec" {
    inline = "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/kubernetes-dashboard-rbac.yaml"
  }

}

resource "scaleway_server" "kubernetes_slave" {
  name = "${format("${var.kubernetes_cluster_name}-slave-%02d", count.index)}"
  depends_on = ["scaleway_server.kubernetes_master"]
  image = "${var.base_image_id}"
  dynamic_ip_required = "${var.dynamic_ip}"
  type = "${var.scaleway_slave_type}"
  count = "${var.kubernetes_slave_count}"
  connection {
    user = "${var.user}"
    private_key = "${file(var.kubernetes_ssh_key_path)}"
  }
  provisioner "local-exec" {
    command = "while [ ! -f ./scw-install.sh ]; do sleep 1; done"
  }
  provisioner "file" {
    source = "scw-install.sh"
    destination = "/tmp/scw-install.sh"
  }
  provisioner "remote-exec" {
    inline = "KUBERNETES_TOKEN=\"${var.kubernetes_token}\" bash /tmp/scw-install.sh slave"
  }
}

