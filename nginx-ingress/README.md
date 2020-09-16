# Running NGINX Ingress on PKS k8s clusters with NSX-T

## Prerequisites

Before performing the procedures in this topic, you must have installed and configured the following:

- PKS v1.2+.
- NSX-T v2.3+.
- A PKS plan with at least 1 master and 2 worker nodes.
- Make sure that the k8s cluster is deployed with priviliged access. Deployment of nginx will fail otherwise.
- Make sure that the k8s cluster is deployed with SecurityContextDeny disabled. Deployment of nginx will fail otherwise.


## Install nginx

Follow the steps below to run nginx on k8s, side by side NSX-T. Nginx will be exposed outside using virtual servers on NSX-T but nginx will be performing the ingress functionality. NSX-T will just be forwarding all the traffic to nginx.

Run the subsequent commands in this tutorial from the home directory of this tutorial i.e istio.

### Step 1: Create the nginx Deployment

Firstly, create the namespace for nginx ingress, along with some ConfigMaps, ServiceAccount, ClusterRole,  Role, RoleBinding, ClusterRolebinding and the Deployment. All these resources will be created by issuing the command below.

```
$ kubectl apply -f install/mandatory.yaml
```


### Step 2: Deploy the nginx service

Then create the nginx service
```
$ kubectl apply -f install/nginx-service.yaml
```
This will expose the nginx POD to NSX-T using type load balancer. After issuing this command, you should be able to see 2 virtual servers in the same k8s cluster's Load Balanncer, with the same IP. One is for http, listening on port 80 and the other virtual server is for https traffic, listening on port 443.


### Step 4: Check the nginx POD

```
kubectl get pods --all-namespaces -l app.kubernetes.io/name=ingress-nginx --watch
NAMESPACE       NAME                                        READY     STATUS    RESTARTS   AGE
ingress-nginx   nginx-ingress-controller-56c5c48c4d-b4hsp   1/1       Running   0          1h
```
The status of ingress-nginx POD is Running which means the nginx ingress controller was deployed susccessfully


### Step 5: Retrieve the nignx-ingress IP

Run the following command to get the nginx-ingress IP

```
$ kubectl get svc -n ingress-nginx

    NAME            TYPE           CLUSTER-IP       EXTERNAL-IP                 PORT(S)                      AGE
    ingress-nginx   LoadBalancer   10.100.200.82    100.64.16.5,172.26.80.100   80:30212/TCP,443:31995/TCP   18h
```
Note down the external IP of the ingress-nginx for your environment. In this case, the nginx ingress LB can be reached at 172.26.80.100 and is listening on port 80 and 443.


### Step 6: Deploying the cafe application

1. Run the following command to change the context to "ingress-nginx" namespace. This is where we will deploy the cafe application
    ```
    $ kubectl config set-context $(kubectl config current-context) --namespace=ingress-nginx
    ```

2. Executing the following commands to deploy the cafe application
    ```
    $ kubectl apply -f complete-example/cafe.yaml
        deployment.extensions/coffee created
        service/coffee-svc created
        deployment.extensions/tea created
        service/tea-svc created

    $ kubectl apply -f complete-example/cafe-secret.yml
        secret/cafe-secret created
    ```
    
3. Deploy the ingress resource for cafe application. Make sure to change the host and hosts value in complete-example/cafe-ingress.yml file to reflect your environment
    ```
    $ kubectl apply -f complete-example/cafe-ingress.yml
        ingress.extensions/cafe-ingress created
    ```

4. Check the POD status to verify that cafe application deployed successfully
    ```
    $ kubectl get pods

        NAME                                        READY     STATUS    RESTARTS   AGE
        coffee-56668d6f78-rzj27                     1/1       Running   0          2m46s
        coffee-56668d6f78-wxvvv                     1/1       Running   0          2m46s
        nginx-ingress-controller-56c5c48c4d-b4hsp   1/1       Running   0          18h
        tea-85f8bf86fd-bskzx                        1/1       Running   0          2m46s
        tea-85f8bf86fd-wcmqx                        1/1       Running   0          2m46s
        tea-85f8bf86fd-xw68j                        1/1       Running   0          2m46s
    ```
    All pods are showing Running which shows that cafe application was deployed successfully

### Step 7: Testing connectivity using the cafe application deployed in step 6

The following commands will test the connectivity externally to verify that our cafe application is reachable using the nginx ingress LB.

1. Populate the IC_IP and IC_HTTPS_PORT variable for the ingress controller. The ingress controller ip(IC_IP) was retrieved in step 5. The cafe application is using port 443 for https traffic

    ```
    $ IC_IP=172.26.80.100
    $ IC_HTTPS_PORT=443
    ```

2. Test the coffe PODs

    Issue the command below to curl your PODs. Note that there is coffee in the url which nginx controller is using to direct traffic to the coffee backend PODs. Issuing the command multiple time round robins the request to the 2 coffee backend PODs as defined in cafe.yaml. The "Server address" field in the curl output identifies the backend POD fullfilling the request

    ```
    $ curl --resolve cafe.lab.local:$IC_HTTPS_PORT:$IC_IP https://cafe.lab.local:$IC_HTTPS_PORT/coffee --insecure
    Server address: 172.25.3.8:80
    Server name: coffee-56668d6f78-wxvvv
    Date: 15/Mar/2019:19:05:54 +0000
    URI: /coffee
    Request ID: 242a10438ab9cc8c93b531db656e9b01
    
    $ curl --resolve cafe.lab.local:$IC_HTTPS_PORT:$IC_IP https://cafe.lab.local:$IC_HTTPS_PORT/coffee --insecure
    Server address: 172.25.3.9:80
    Server name: coffee-56668d6f78-rzj27
    Date: 15/Mar/2019:19:05:55 +0000
    URI: /coffee
    Request ID: 6d8bafb54e5c7a1c495e0790516cfa88
    ```
    

3. Test the tea PODs

    The cafe.yaml file deployed 3 replicas of the tea POD so issuing the curl command multiple time distributes the request on these 3 PODs. This can be verified using the "Server address" field in the outputs below.

    ```
    $ curl --resolve cafe.lab.local:$IC_HTTPS_PORT:$IC_IP https://cafe.lab.local:$IC_HTTPS_PORT/tea --insecure
    Server address: 172.25.3.10:80
    Server name: tea-85f8bf86fd-bskzx
    Date: 15/Mar/2019:19:12:23 +0000
    URI: /tea
    Request ID: e3ca80b2254fc47a96735b99615ebfb4
    
    $ curl --resolve cafe.lab.local:$IC_HTTPS_PORT:$IC_IP https://cafe.lab.local:$IC_HTTPS_PORT/tea --insecure
    Server address: 172.25.3.11:80
    Server name: tea-85f8bf86fd-wcmqx
    Date: 15/Mar/2019:19:12:24 +0000
    URI: /tea
    Request ID: 546e2deb5e6dc0f11cc677e21b764976
    
    $ curl --resolve cafe.lab.local:$IC_HTTPS_PORT:$IC_IP https://cafe.lab.local:$IC_HTTPS_PORT/tea --insecure
    Server address: 172.25.3.12:80
    Server name: tea-85f8bf86fd-xw68j
    Date: 15/Mar/2019:19:12:25 +0000
    URI: /tea
    Request ID: ef81fc9439705a2990d3984ec0a0464e
    ```

    Alternatively, a DNS entry can be added for cafe.lab.local(hostname used in my environment) to map to 172.26.80.100 to access the url directly from the browser.


References:
- https://kubernetes.github.io/ingress-nginx/deploy/#prerequisite-generic-deployment-command
- https://github.com/nginxinc/kubernetes-ingress/tree/master/examples/complete-example
