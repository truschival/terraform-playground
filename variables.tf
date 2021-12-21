###
# mandatory variables
###

variable "ssh_pub_file" {
  description = "ssh public key"
  type        = string
}

variable "ssh_user" {
  description = "username for ssh key"
  type        = string
}

variable "project" {
  description = "cloud project"
  type        = string
}

### optional variables with default values ##########

variable "region" {
  description = "region where to spin up resources"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "zone within region where to spin up resources"
  type        = string
  default     = "europe-west1-c"
}

variable "master_machine_type" {
  description = "VM machine type for control plane masters"
  type        = string
  default     = "e2-standard-4"
}

variable "worker_machine_type" {
  description = "VM machine type for worker nodes"
  type        = string
  default     = "n1-standard-2"
}

variable "master_node_name" {
  description = "name prefix for control plane master nodes"
  type        = string
  default     = "tf-cp"
}

variable "vpc_net_name" {
  description = "name for the cloud network"
  type        = string
  default     = "cluster-vm-net"
}

variable "worker_node_prefix" {
  description = "name prefix for cluster worker nodes"
  type        = string
  default     = "tf-worker"
}

variable "worker_count" {
  description = "number of workers to instatiate"
  type        = number
  default     = 2
}

variable "image" {
  description = "Image to use for machines"
  type        = string
  default     = "debian-11-bullseye-v20211105"
}
