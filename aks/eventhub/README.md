
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
 * StorageAccount, to be used by the Elastic Agent to store the state (is this accurate?)
 * A container inside the Storage Account, to be used by the Elastic Agent to store its state

## 2. Azure Resource to monitor

For this demo, we are gathering K8s logs from an AKS cluster. Too keep things simple, we'll just gather the logs of the AKS cluster where our Elastic - as ECK - is running on. 

### 2.1 Create Diagnostic Settings

For demonstration purposes, we're creating the Diagnostic Setting manually over the Azure console.

 * Go to the resource to monitor (the AKS cluster)
 * Go to "Monitoring" --> "Diagnostic Settings" 
 * Create a new Diagnostic Setting
 * Select all "Kubernetes" categories
 * In the "Destination details", select "Stream to an event hub"
 * Provide the Subscription, the Event hub namespace, the Event hub name and the Event hub policy name
 * Save and exit 

### 2.2 Modify Elastic Agent endpoint

Only needed if the elastic cluster is deployed in the same K8s cluster as the agent, as is the case here. Otherwise, TLS must be configured, and all the services exposed accordingly.

Since in this demo the elastic agent and the elasticsearch cluster are running in the same AKS cluster, to simplify TLS configuration we deactivate TLS for the communication between the agents and elasticsearch. Since we have fleet-managed agents, this configuration is not up to the agent but up to Kibana and Fleet. Go to the kibana manifest:
```
vi kibana.yaml
```
Make sure the endpoint for elasticsearch is using http and not https:
```
config:
  xpack.fleet.agents.elasticsearch.hosts: ["http://elasticsearch-es-http.default.svc:9200"]
  xpack.fleet.agents.fleet_server.hosts: ["https://fleet-server-agent-http.default.svc:8220"]
```

The communication between the agents and fleet is TLS encrypted. However, the certificate check is deactivated, so the default self-signed certificated configured for fleet works for the communication. 

_NOTE: this is not that nice actually. It would be better to expose both the elasticsearch and fleet server services externally, providing trusted TLS certificates issued by Let's Encrypt, configuring the ingress accordingly, same I did with Kibana_

### 2.3 Add Elastic Integration 

Go to your Kibana to create the Azure Logs integration.

 * Go to "Integrations"
 * Add an "Azure Logs integration"
 * As the Integration name, write "aks-logs-integration"
 * As Event Hub, write the name of the one we created before
 * As the Connection String, paste the one you'll find under the Event Hub Namespace, in the Azure Console, when selecting "Shared access policies", then selecting the authorization rule created before. From there you can copy the "Primary key".
 * As "Storage Account", write the name the one created before
 * The "Storage Account Key" can be found in the Azure Console, under the Storage Account "Access keys". There you can copy the "key 1"
 * Further down, select "Collect events from Event Hub", "Azure Event Hub Input" and "Parse azure message"
 * In the section "Where to add this integration?", select "New Hosts" and "Create agent policy". Name it "aks-logs-agent-policy".
 * Click on "Save and Continue". When prompted, select "Add Elastic Agent to your hosts"

### 2.4 Add and Install Elastic Agent

We are going to install the elastic agent in K8s via manifest. Too keep thing simple, we're installing the agent in the same AKS cluster where ECK is running, and which we want to monitor. 

In the wizard for the agent installation, in the second step "Install Elastic Agent on your host", go to"Kubernetes" and copy-paste the sample manifest. 

Paste the copied manifest in a new file elastic-agent.yaml and make the following modifications:
 
 * Deploy the agent as a StatefulSet instead of a DaemonSet
 * Modify the namespace for the StatefulSet and all related resources (ServiceAccount, etc) in the manifest to "default"

Deploy the manifest:
```
kubectl apply -f agent.yaml
```

After a couple of seconds, in the wizard you'll see "Agent enrollment confirmed", meaning the agent we just deployed was able to connect to our Fleet Server. 

Shortly afterwards, you should get the notification that the agent is sending data.

Go to Discover and filter the agent name to be the elastic agent deployed for the aks-logs integration. You'll see the data being sent by AKS to the EventHub, which is pulled by the agent and send to Elasticsearch:
-------                             ------------     -----------------     -----------
| AKS | --- DiagnosticSettings ---> | EventHub | --> | Elastic Agent | --> | Elastic |
-------                             ------------     -----------------     -----------

 


