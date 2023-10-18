# Elastic Cloud on Kubernetes

_A fully managed service is a very convenient approach to run software services but, depending on the use case, not always the most suitable way. Kubernetes brings cloud-native advantages to both on-premises and cloud-hosted CaaS environments. Elastic Cloud on Kubernetes (ECK) extends the K8s APIs with its operator and custom resources to run Elasticsearch as a cloud-native K8s application._

This guide include the terraform files and K8s manifest needed to deploy a small test ECK cluster in GKE.

__This is not an Elastic official documentation, but my notes and observations during the deployment of a small ECK cluster on GCP.__

### GCP

A GCP account is necessary.

First, create a service account and assign permissions. Following roles did I need to assign to my service account:
 * DNS Administrator
 * Compute Network Admin
 * Kubernetes Engine Cluster Admin
 * Service Account User

_NOTE: These are too many permissions - it's better to follow the principle of least privilege and create a custom role containing exactly the permissions needed and not more._

### Terraform

We rely on terraform to set up the infrastructure on GKE. In [main.tf](terraform/main.tf) we define following resources:
 * A VPC network and a subnet
 * A public static IP - for exposing Kibana later  
 * A K8s cluster - removing the default node pool immediately upon creation
 * A separately managed node pool - this is the recommended way
 * A DNS A Record - pointing to the public static IP generated before

For 3 elasticsearch nodes, assuming we're planing to dedicate this K8s cluster to our ES cluster, it's recommended to avoid several ES nodes on the same worker node: we are going to need 3 worker nodes. 

Providing the region under _location_ and saying the node count is 1, GKE will create a worker node in each zone of the region, so we'll end up with three nodes. 

Create a file _myvars.tfvars_ including the variables which need to be defined. They can be find under the file [variables.tf](terraform/variables.tf). 

Then run:
```
eramon@applejuice gke % cd terraform
eramon@applejuice terraform % terraform init
```
And:
```
eramon@applejuice terraform % terraform apply -var-file=myvars.tfvars
```

### K8s Cluster

To interact with the GKE cluster, following tools must be installed on the local machine:
 * kubectl
 * google-cloud-sdk

Initialize the google cloud sdk:
```
eramon@applejuice terraform % gcloud init
Welcome! This command will take you through the configuration of gcloud.
```

Install gke-gloud-auth-plugin:
```
eramon@applejuice terraform % gcloud components install gke-gcloud-auth-plugin
```

Configure gcloud to use the K8s cluster access credentials:
```
eramon@applejuice terraform % gcloud container clusters get-credentials $(terraform output -raw kubernetes_cluster_name) --region $(terraform output -raw kubernetes_cluster_region)
```

And after that, my kubectl automagically points to the right cluster:
```
eramon@applejuice terraform % cd ../k8s
eramon@applejuice k8s % kubectl cluster-info
Kubernetes control plane is running at https://35.234.83.72
GLBCDefaultBackend is running at https://35.234.83.72/api/v1/namespaces/kube-system/services/default-http-backend:http/proxy
KubeDNS is running at https://35.234.83.72/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://35.234.83.72/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy
```

### Nginx ingress

To use helm to install K8s resources on our cluster, following software must be installed on the local machine:
 * helm

The loadBalancerIP of the ingress controller must be set to the public IP we created with Terraform. 

Install ingress-nginx manually using helm:
```
eramon@applejuice k8s % helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.loadBalancerIP=$(terraform output -raw ingress_static_ip)
```
This creates a service of type LoadBalancer and assigns as external IP the one provided in the terraform output: this is the static public IP address we reserved in GCP which also corresponds to the created DNS record.

_NOTE: I'm used to the ingress-nginx controller, but it is also possible to use the GKE ingress controller._

### Cert-manager

Install cert-manager via helm. First add the helm repository:
```
eramon@applejuice k8s % helm repo add jetstack https://charts.jetstack.io
"jetstack" has been added to your repositories
```
Update the helm repository:
```
eramon@applejuice k8s % helm repo update
```
Install cert-manager, including the CRDs:
```
eramon@applejuice k8s % helm install \                                   
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.11.0 \
  --set installCRDs=true
```

### ECK

ECK is composed by the Custom Resource Definitions and the Operator.

Manually install the latest CRDs using directly the remotemanifest:
```
eramon@applejuice k8s % kubectl apply -f https://download.elastic.co/downloads/eck/2.6.1/crds.yaml
```
Manually install the latest operator version using directly the remote manifest:
```
eramon@applejuice k8s % kubectl apply -f https://download.elastic.co/downloads/eck/2.6.1/operator.yaml
```
_NOTE: it's also possible to include the CRDs and the operator directly in the kustomization.yaml file. I do it separately here for better ilustrating the necessary steps of the installation._

### Kustomize

For the remaining K8s ressources, I rely on Kustomize to deploy the K8s resources in a reproducible manner.

The manifests of the elastic resources are based on the recipes provided in the ECK github, with minimal modifications (see links below).

### Cluster Issuer and Ingress

The clusterissuer and the ingress are included in the [kustomization.yaml](k8s/kustomization.yaml) file:
 * The clusterissuer uses let's encrypt to issue a trusted SSL certificate for the kibana frontend
 * The [ingress.yaml](k8s/ingress.yaml.sample) uses the installed ingress-nginx controller and instructs the cluster issuer to assign the SSL certificate to the kibana endpoint

Note that the provided ingress file is a sample: it must be modified to contain the real domain hosting kibana.

### Elasticsearch

The Elasticsearch ressource - available now as a custom resource, since we install the CRDs - is included in the [kustomization.yaml](k8s/kustomization.yaml) file.

Small deployment following best practices and hardware recommendations:
 * 3 elasticsearch nodes 
 * These 3 nodes represent the hot tier of the cluster
 * Each ES node claim a persistent volume of 1Gi (*)
 * These 3 nodes also act as the master nodes
 * 1 elasticsearch node on each worker node (**)

(*) This is a small storage for an ES node, but this is a test cluster. The storage class is the default of GKE.

(**) We don't need to explicitely configure this. By default, ECS sets a default podAntiAffinity rule to avoid the scheduling of several elasticsearch nodes from the same cluster on the same host:

For resource requests and limits, we rely on the default values set by the ECK operator. That means we don't need to explicitely define them in the elasticsearch manifest (see links below)

### Kibana

The Kibana ressource - available now as a custom ressource - is included in the [kustomization.yaml](k8s/kustomization.yaml) file.

The SSL termination is handled by the ingress, so I did following modifications to the kibana manifest:
 * Deactivate TLS
 * Change the type of the service to ClusterIP - default in the samples was LoadBalancer

### Fleet

Fleet - available as a custom resource - is included in the [kustomization.yaml](k8s/kustomization.yaml) file.

### Elastic Agent

The Elastic Agent - available as a custom resource - is included in the [kustomization.yaml](k8s/kustomization.yaml) file.

### Deploy

Install Clusterissuer, Ingress, Elasticsearch and Kibana using kustomize:
```
eramon@applejuice k8s % kubectl apply -k .
```
Done. Kibana is now accessible on the browser under the configured hostname, with a valid SSL certificate.

### Links

Terraform - Provision a GKE Cluster:
https://developer.hashicorp.com/terraform/tutorials/kubernetes/gke

ECK:
https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html

ECK Recipes:
https://github.com/elastic/cloud-on-k8s/tree/main/config/recipes

Helm:
https://kubernetes.github.io/ingress-nginx

ECK Node Scheduling:
https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-advanced-node-scheduling.html

ECK default resource allocation:
https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-managing-compute-resources.html#k8s-default-behavior
