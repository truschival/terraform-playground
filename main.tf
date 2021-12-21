# Terraform block defines required providers
# It worked without this block when running terraform init
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.1.0"
    }
  }
}

provider "google" {
  # Set credential in file
  # credentials = file("<NAME>.json")
  # Better: use `gcloud auth application-default login`
  project = var.project
  region  = var.region
  zone    = var.zone
}

## Master VM
resource "google_compute_instance" "master" {
  name         = var.master_node_name
  machine_type = var.master_machine_type
  tags         = ["cluster", "master"]
  description  = "Cluster control plane master"

  # hostname = "someothername" 
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.image
      size  = 15 # Size in GB
    }
  }

  metadata = {
    CRIO                = 1
    CRIO_DISTRO_REPO    = "Debian_11"
    CRIO_DISTRO_K8S_VER = "1.21"
    NODE_IS_CP_MASTER   = "1"
    # calico deployment (already configured for IPV4_POOL 192.168.0.0/16)
    cni_deploy = "${file("./k8s-setup/calico.yaml")}"
    # Default cluster init file for cri-o
    kubeadm_cfg = "${file("./k8s-setup/kubeadm-crio.yaml")}"
    # k8s ca certificate and key (only on control plane) for
    ca_cert = "${file("./k8s-setup/ca.crt")}"
    ca_key  = "${file("./k8s-setup/ca.key")}"
    # Digest of pubkey for joining, I am sure there is a nother way than:
    #   openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
    #   openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex
    ca_pubkey_digest = "a19096a4f963f29b85cd86353de3cc0f9f8a9d9fc7ad0b9bfcb7a6f463faa3f6"
    # Token to join control plan, set both in master and workers
    k8s_cp_token = "ry5fyu.sboztj8p2ftru0zg"
    # run this scrip on startup, no ssh-login needed
    startup-script = "${file("./k8s-setup.sh")}"
    # Can be a list of keys
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_file)}"
  }

  network_interface {
    # A default network is created for all GCP projects
    network    = module.vpc.network_name
    subnetwork = "cluster-vm-subnet-1"
    #Removing "Access Config" -> no external ip
    access_config {
    }
  }
}


## Worker machines
resource "google_compute_instance" "workers" {
  machine_type = var.worker_machine_type
  tags         = ["cluster", "worker"]
  description  = "worker node"

  # hostname = "someothername" 
  allow_stopping_for_update = true

  count = var.worker_count
  name  = "${var.worker_node_prefix}-${count.index}"

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  metadata = {
    CRIO                = 1
    CRIO_DISTRO_REPO    = "Debian_11"
    CRIO_DISTRO_K8S_VER = "1.21"
    # Digest of pubkey for joining, I am sure there is a nother way than:
    #   openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
    #   openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex
    ca_pubkey_digest = "a19096a4f963f29b85cd86353de3cc0f9f8a9d9fc7ad0b9bfcb7a6f463faa3f6"
    # k8s master name
    k8s_cp_master = var.master_node_name
    # Token to join control plan, set both in master and workers
    k8s_cp_token = "ry5fyu.sboztj8p2ftru0zg"
    # run this scrip on startup, no ssh-login needed
    startup-script = "${file("./k8s-setup.sh")}"
    # Can be a list of keys
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_file)}"
  }

  # Worker node depend on master
  depends_on = [google_compute_instance.master]

  network_interface {
    # A default network is created for all GCP projects
    network    = module.vpc.network_name
    subnetwork = "cluster-vm-subnet-1"
    # Removing "Access Config" -> no external ip but for some weird reasons
    # Google also needs the external IP for internet access, without
    # access_config, i.e. external IP there is no access to the internet and
    # therefore no apt-get...
    # https://cloud.google.com/vpc/docs/configure-private-google-access
    access_config {
    }
  }
}


## Configure a VPC for the VMs
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "4.0.1"

  project_id   = var.project
  network_name = var.vpc_net_name
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name           = "cluster-vm-subnet-1"
      subnet_ip             = "10.127.10.0/24"
      subnet_region         = var.region
      subnet_private_access = "true"
      subnet_flow_logs      = "true"
      description           = "Subnet to connect cluster nodes"
    }
  ]
}

## Firewall rule for VPC
# According to https://cloud.google.com/vpc/docs/vpc:
#   Traffic to and from instances can be controlled with network firewall
#   rules. Rules are implemented on the VMs themselves, so traffic can only be
#   controlled and logged as it leaves or arrives at a VM
module "firewall_rules" {
  source       = "terraform-google-modules/network/google//modules/firewall-rules"
  project_id   = var.project
  network_name = module.vpc.network_name

  rules = [{
    name                    = "allow-standard-ingress"
    description             = null
    direction               = "INGRESS"
    priority                = null
    ranges                  = ["0.0.0.0/0"]
    source_tags             = null
    source_service_accounts = null
    target_tags             = null
    target_service_accounts = null
    allow = [
      {
        protocol = "tcp"
        ports    = ["22"]
      },
      {
        protocol = "tcp"
        ports    = ["80", "443", "8080"]
      },
      {
        protocol = "tcp"
        ports    = ["6443", "10250", "10257", "10259"]
      }
    ]
    deny = []

    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }]
}
