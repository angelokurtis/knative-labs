#!/bin/sh

set -e

# create a cluster with the local registry enabled in containerd
cat <<EOF | kind create cluster --name knative-cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.17.11@sha256:5240a7a2c34bf241afb54ac05669f8a46661912eab05705d660971eeb12f6555
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 30000
    hostPort: 80
  - containerPort: 30001
    hostPort: 443
  - containerPort: 30002
    hostPort: 15021
EOF

# connect to kind's cluster
kubectl ctx kind-knative-cluster

# install Istio
cat <<EOF | istioctl install -f -
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  addonComponents:
    pilot:
      enabled: true
    prometheus:
      enabled: false
  components:
    ingressGateways:
      - name: istio-ingressgateway
        k8s:
          nodeSelector:
            ingress-ready: "true"
          service:
            ports:
              - name: status-port
                port: 15021
                targetPort: 15021
                nodePort: 30002
              - name: http2
                port: 80
                targetPort: 8080
                nodePort: 30000
              - name: https
                port: 443
                targetPort: 8443
                nodePort: 30001
  values:
    gateways:
      istio-ingressgateway:
        type: NodePort
    global:
      proxy:
        autoInject: disabled
      useMCP: false
      jwtPolicy: first-party-jwt
EOF

# installing the Serving CRDs
kubectl apply -f ./manifests/knative/v0.18.0/serving/crds
# installing the core components of Serving
kubectl create namespace knative-serving
kubectl apply -f ./manifests/knative/v0.18.0/serving/core --namespace knative-serving
# installing the Knative Istio controller
kubectl apply -f ./manifests/knative/v0.18.0/serving/controllers/istio --namespace knative-serving

# installing the Eventing CRDs
kubectl apply -f ./manifests/knative/v0.18.0/eventing/crds
# installing the core components of Eventing
kubectl create namespace knative-eventing
kubectl apply -f ./manifests/knative/v0.18.0/eventing/core --namespace knative-eventing
# installing a default Channel layer
kubectl apply -f ./manifests/knative/v0.18.0/eventing/channels/in-memory-channel --namespace knative-eventing
# installing a Broker layer
kubectl apply -f ./manifests/knative/v0.18.0/eventing/brokers/mt-channel-broker --namespace knative-eventing

# monitor the Knative Serving components to be completed
kubectl wait --for=condition=Ready pods --all --namespace knative-serving
# monitor the Knative Eventing components to be completed
kubectl wait --for=condition=Ready pods --all --namespace knative-eventing
