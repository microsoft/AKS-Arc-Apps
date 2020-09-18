We recommend EFK (Elastic-search, Filebeat and Kibana) to setup containers logging on the cluster.

Elastic-search - Stores the logs.

Filebeat - Forwards the containers logs to Elastic-search cluster.

Kibana - Elastic-search UI to view the logs.

***Note: Since elasticsearch can be configured/customized in many ways we are not providing script to deploy it. Rather we are recommending official elastic URLs for detailed instructions.***
* Detailed steps to configure elasticsearch cluster and kibana can be found here https://www.elastic.co/blog/introducing-elastic-cloud-on-kubernetes-the-elasticsearch-operator-and-beyond
* Detailed steps to configure Filebeat https://www.elastic.co/guide/en/beats/filebeat/current/index.html

