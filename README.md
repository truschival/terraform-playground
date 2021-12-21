# Terraform for Google Compute Engine Playground

This is not production quality code. This is my Terraform + GCP learning
effort. I used the lab examples from Linux Foundation Course for Kubernetes
Admin (CKA) to practice k8s cluster setup in VMs with terraform.

This shows the use-case is somewhat construed, for this you would probably not
spin up VMs and install a cluster but go directly to GKE.

**!Warning!** The folder [k8s-setup](./k8s-setup) contains a CA secret-key and
cert! Make sure you use other files and keep them secret!  The script
[k8s-setup.sh](./k8s-setup.sh) also still has the *join-token* and the
hash of the above *CA-cert* hard coded. Make sure you fix it!

## Required tools

* [Hashicorp terraform](https://www.terraform.io/downloads.html)
* [google cloud sdk](https://cloud.google.com/sdk/docs/install)

## What will be Created

I created a VPC network ``vpc_net_name`` with the subnet "cluster-vm-subnet-1"
in the range 10.127.10.0/24 to keep my VMs separate from the other VMs in the
cloud project.

I played around with firewall rules but have not gone far. Currently I suppose I
block all traffic except ``ssh`` port 22 and kube-apiserver port 6443 - not sure
if this makes sense.

The specification creates one control plane *master* node virtual machine
instance with ``worker_count`` *worker node* instances.

I dabbled with the ``metadata`` property for the VMs to inject information to
the ``startup-script``.  The startup-script [./k8s-setup.sh](./k8s-setup.sh)
installs required packages and with information form the metadata creates a
cluster-control-plane and makes worker-nodes to join the control plane.

## Required Terraform variables

To use and play around with the code you need a Google Cloud account with a
project where you have permission to start VMs.

Create terraform-variables in the file ``./terraform.tfvars`` with these
mandatory variables:

	project      = <your cloud project id>
	ssh_user     = <your cloud user name>
	ssh_pub_file = <path to ssh public key>

## Usage

1.  Log in to google cloud to authenticate:\
	``gcloud auth login`` \
	A browser window will open and ask for your credentials. For more options
    see [gcloud](https://cloud.google.com/sdk/gcloud/reference)

2.  Initialize terraform, i.e. download required modules
	``terraform init``

3.  Check what terraform is about to instatiate
	``terraform plan``

4.  Actually instatiate VMs
	``terraform apply``

5.  You can now log in to the control plane master (find the exteral IP for the
    VM in google cloud console)
	``ssh <cloud_user>@public.ip``
	get the kubeconfig for local use.

6.  When no longer needed destroy the instances because they cause costs.
	``terraform destroy``

### Notes:

*  It takes quite some time (3 min) for the *worker nodes* to join the cluster.

*  ``terraform destroy`` blocks on destroying the VPC network because it takes
   time to shut down the machines. I have to run ``terraform destroy`` a second
   time.
