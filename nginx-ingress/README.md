# Running NGINX Ingress on Kubernetes clusters created using AKS on HCI

## Prerequisites

Before performing the procedures in this topic, you must have installed and configured the following:

- AKSHCI +v0.9.3.1
- An AKSHCI Target Kubernetes Cluster with least 1 master and 2 worker nodes.

## Install nginx

Run the subsequent commands in this tutorial from the home directory of this tutorial i.e nginx-ingress.

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
This will expose the nginx POD using type load balancer. 

### Step 4: Check the nginx POD

```
kubectl get pods --all-namespaces -l app.kubernetes.io/name=ingress-nginx --watch
NAMESPACE       NAME                                       READY   STATUS    RESTARTS   AGE
ingress-nginx   nginx-ingress-controller-8f68db9b5-8f2m7   0/1     Running   0          15s
```
The status of ingress-nginx POD is Running which means the nginx ingress controller was deployed susccessfully


### Step 5: Retrieve the nignx-ingress IP

Run the following command to get the nginx-ingress IP

```
$ kubectl get svc -n ingress-nginx

    NAME            TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                      AGE
    ingress-nginx   LoadBalancer   10.106.174.75   10.137.198.21   80:30623/TCP,443:30102/TCP   22s
```
Note down the external IP of the ingress-nginx for your environment. In this case, the nginx ingress LB can be reached at 10.137.198.21 and is listening on port 80 and 443.


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

        NAME                                       READY   STATUS    RESTARTS   AGE
        coffee-755d68dd75-2c2sq                    1/1     Running   0          118s
        coffee-755d68dd75-zqjl7                    1/1     Running   0          118s
        nginx-ingress-controller-8f68db9b5-8f2m7   1/1     Running   0          5m37s
        tea-6c74d89d87-96cw9                       1/1     Running   0          118s
        tea-6c74d89d87-lsvzx                       1/1     Running   0          118s
        tea-6c74d89d87-srv5q                       1/1     Running   0          118s
    ```
    All pods are showing Running which shows that cafe application was deployed successfully

### Step 7: Testing connectivity using the cafe application deployed in step 6

The following commands will test the connectivity externally to verify that our cafe application is reachable using the nginx ingress LB.

1. Populate the IC_IP and IC_HTTPS_PORT variable for the ingress controller. The ingress controller ip(IC_IP) was retrieved in step 5. The cafe application is using port 443 for https traffic

    ```
    $ $IC_IP="10.137.198.21"
    $ $IC_HTTPS_PORT=443
    ```

2. Test the coffe PODs

    Issue the command below to curl your PODs. Note that there is coffee in the url which nginx controller is using to direct traffic to the coffee backend PODs. Issuing the command multiple time round robins the request to the 2 coffee backend PODs as defined in cafe.yaml. The "Server address" field in the curl output identifies the backend POD fulfilling the request

    ```
    $ curl.exe --resolve cafe.lab.local:$($IC_HTTPS_PORT):$($IC_IP) "https://cafe.lab.local:$($IC_HTTPS_PORT)/coffee" --insecure
    Server address: 10.244.2.5:80
    Server name: coffee-755d68dd75-2c2sq
    Date: 18/Sep/2020:23:25:51 +0000
    URI: /coffee
    Request ID: 477f489b1a19a6c4d90c0285552d626a
    
    $ curl.exe --resolve cafe.lab.local:$($IC_HTTPS_PORT):$($IC_IP) "https://cafe.lab.local:$($IC_HTTPS_PORT)/coffee" --insecure
    Server address: 10.244.1.6:80
    Server name: coffee-755d68dd75-zqjl7
    Date: 18/Sep/2020:23:27:23 +0000
    URI: /coffee
    Request ID: 336c0222984c0a1b67e6caec74307235
    ```
    

3. Test the tea PODs

    The cafe.yaml file deployed 3 replicas of the tea POD so issuing the curl command multiple time distributes the request on these 3 PODs. This can be verified using the "Server address" field in the outputs below.

    ```
    $ curl.exe --resolve cafe.lab.local:$($IC_HTTPS_PORT):$($IC_IP) "https://cafe.lab.local:$($IC_HTTPS_PORT)/tea" --insecure
    Server address: 10.244.2.6:80
    Server name: tea-6c74d89d87-96cw9
    Date: 18/Sep/2020:23:28:04 +0000
    URI: /tea
    Request ID: 069324034e9333c193ffd6f584f4bae4
    
    $ curl.exe --resolve cafe.lab.local:$($IC_HTTPS_PORT):$($IC_IP) "https://cafe.lab.local:$($IC_HTTPS_PORT)/tea" --insecure
    Server address: 10.244.2.6:80
    Server name: tea-6c74d89d87-96cw9
    Date: 18/Sep/2020:23:28:04 +0000
    URI: /tea
    Request ID: 069324034e9333c193ffd6f584f4bae4
    
    ```

    Alternatively, a DNS entry can be added for cafe.lab.local(hostname used in my environment) to map to 172.26.80.100 to access the url directly from the browser.


References:
- https://kubernetes.github.io/ingress-nginx/deploy/#prerequisite-generic-deployment-command
- https://github.com/nginxinc/kubernetes-ingress/tree/master/examples/complete-example
