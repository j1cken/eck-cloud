_Disclaimer: this is NOT an official documentation, just my notes from my own experiments._ 

_See the bottom of this page for links to the Elastic Documentation._

## The Small Event-Hub Demo

This demo features:

 * An Azure Logs Elastic Integration
 * An Elastic Agent deployed as StatefulSet in K8s
 * An AKS Cluster, which is the resource to be monitored i.e. to gather logs from
 * An EventHub, used by the Azure Logs Integration and the Elastic Agent to send and receive data respectively
 * An Elastic cluster, including Kibana and Fleet, to store and visualize the ingested logs

## 0. Pre-requisites

 * An existing resource group to deploy the Azure resources
 * An Elastic Cluster, either in Cloud or on ECK 
 * A Fleet / Integration Server, configured to communicate with Elasticsearch and Kibana
 * An AKS cluster, whose Logs will be sent to Elastic via EventHub and ElasticAgent

Refer to [aks](../README.md) for an AKS cluster with ECK running on it, including a Fleet Server, which can be used for installing ECK, deploying the agent and as the logs source 

## 1. Terraform

Following Azure resources are configured for deployment via Terraform:

 * EventHub Namespace
 * EventHub
 * Authorization Rule for the Elastic Agent to pull data from the EventHub (permission: send)
 * StorageAccount, to be used by the Elastic Agent
 * A container inside the Storage Account, to be used by the Elastic Agent

## 2. Azure Resource to monitor

For this demo, we are gathering K8s logs from an AKS cluster. Too keep things simple, we'll just gather the logs of the AKS cluster where our Elastic - as ECK - is running on. 

### 2.1 Create Diagnostic Settings

For demonstration purposes, we're creating the Diagnostic Setting manually over the Azure console:

 * For the AKS cluster, create a new Diagnostic Setting under "Monitoring"
 * As the data to be shipped, select all "Kubernetes" categories
 * Configure the destination so the data is streamed to an event hub, providing the subscription, event-hub namespace, event-hub name and event-hub policy name

### 2.2 Add Elastic Integration 

Create an Azure Logs integration in Kibana. You'll need following parameters of the Azure resources created before:

 * EventHub name
 * EventHub namespace
 * Connection String (primary key) for the EventHub namespace
 * Storage Account

In the integration configuration, "Collect events from Event Hub" needs to be activated. 

Create a new agent policy for this integration, then proceed to the elastic agent installation.
 
### 2.3 Note about TLS 

In this demo, it's foreseen that the agent is deployed in the same K8s cluster as Elastic, therefore TLS is deactivated for the communication between the agent and Elasticsearch, since the elasticsearch service is not exposed outside the cluster. The sames apply to the communication between the agent and fleet: even if in this case it is TLS encrypted, the certificate check on the agent side is deactivated. 

The elasticsearch endpoint and its protocol (http), as well as the fleet server endpoint, are defined in the following two lines in the [kibana manifest](../k8s/kibana.yml):
```
config:
  xpack.fleet.agents.elasticsearch.hosts: ["http://elasticsearch-es-http.default.svc:9200"]
  xpack.fleet.agents.fleet_server.hosts: ["https://fleet-server-agent-http.default.svc:8220"]
```

### 2.4 Install Elastic Agent

Once the bit about TLS is clarified, let's proceed to deploy the [elastic agent](elastic-agent.yaml).

As mentioned before, to keep things simple, we're installing the agent in the same AKS cluster where ECK is running and which we want to monitor. 

Before deploying the agent, we need to generate a secret with the fleet enrollment token:
```
kubectl create secret generic fleet-token --from-literal=token="<FLEET_TOKEN>"
```
You can find the fleet enrollment token in Kibana, under "Fleet" and then "Settings".

Deploy the [elastic agent](elastic-agent.yaml):
```
kubectl apply -f elastic-agent.yaml
```
Two remarks about the elastic agent manifest:
 
 * I'm not using ECK for deploying the agent, even if the CRD is deployed in the cluster and an agent resource is available. The reason is that the CR installs as a DaemonSet, which makes a lot of sense for a K8s integration, where one agent must be installed on each K8s worker node, but makes little sense for the EventHub use case
 * For an Elastic Integration featuring Azure Logs and the EventHub, the recommendation is to have one agent for each EventHub, scaling to more replicas if the load requires it. In this case, in order for each agent to properly handle its own state, the best option seems to be to deploy the agent as a StatefulSet

After a couple of seconds, in the wizard you'll see "Agent enrollment confirmed", meaning the agent we just deployed was able to connect to our Fleet Server. 

Shortly afterwards, you should get the notification that the agent is sending data.

Go to Discover and filter the agent name to be the elastic agent deployed for the aks-logs integration. You'll see the data being sent by AKS to the EventHub, which is pulled by the agent and send to Elasticsearch:

| AKS | --- DiagnosticSettings ---> | EventHub | --> | Elastic Agent | --> | Elastic |

__References - Elastic Documentation:__ 
 * [Monitor Microsoft Azure with Elastic Agent](https://www.elastic.co/guide/en/observability/current/monitor-azure-elastic-agent.html)
 * [Run Elastic Agent on K8s managed by Fleet](https://www.elastic.co/guide/en/fleet/current/running-on-kubernetes-managed-by-fleet.html)
 * [Choose the Deployment Model](https://github.com/elastic/cloud-on-k8s/blob/main/docs/orchestrating-elastic-stack-applications/agent-fleet.asciidoc#customize-elastic-agent-configuration)


