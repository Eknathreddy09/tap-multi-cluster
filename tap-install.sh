#!/bin/bash
dockerusername=$(yq '.buildservice.kp_default_repository_username' $HOME/tap-multi-cluster/tap-values-build.yaml)
dockerpassword=$(yq '.buildservice.kp_default_repository_password' $HOME/tap-multi-cluster/tap-values-build.yaml)
tanzunetusername=$(yq '.buildservice.tanzunet_username' $HOME/tap-multi-cluster/tap-values-build.yaml)
tanzunetpassword=$(yq '.buildservice.tanzunet_password' $HOME/tap-multi-cluster/tap-values-build.yaml)
dockerhostname=$(yq '.ootb_supply_chain_testing_scanning.registry.server' $HOME/tap-multi-cluster/tap-values-build.yaml)
docker login $dockerhostname -u $dockerusername -p $dockerpassword
docker login registry.tanzu.vmware.com -u $tanzunetusername -p $tanzunetpassword
export INSTALL_REGISTRY_USERNAME=$dockerusername
export INSTALL_REGISTRY_PASSWORD=$dockerpassword
export INSTALL_REGISTRY_HOSTNAME=$dockerhostname
echo "################ Developer namespace in tap-install #####################"
cat <<EOF > developer.yaml
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
secrets:
  - name: registry-credentials
  - name: tap-registry
imagePullSecrets:
  - name: registry-credentials
  - name: tap-registry
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-deliverable
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deliverable
subjects:
  - kind: ServiceAccount
    name: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-workload
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workload
subjects:
  - kind: ServiceAccount
    name: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-permit-app-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: app-viewer
subjects:
- kind: Group
  name: "namespace-developers"
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: namespace-dev-permit-app-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: app-viewer-cluster-access
subjects:
- kind: Group
  name: "namespace-developers"
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: scanning.apps.tanzu.vmware.com/v1beta1
kind: ScanPolicy
metadata:
  name: scan-policy
spec:
  regoFile: |
    package policies

    default isCompliant = false

    # Accepted Values: "Critical", "High", "Medium", "Low", "Negligible", "UnknownSeverity"
    violatingSeverities := []
    ignoreCVEs := []

    contains(array, elem) = true {
      array[_] = elem
    } else = false { true }

    isSafe(match) {
      fails := contains(violatingSeverities, match.Ratings.Rating[_].Severity)
      not fails
    }

    isSafe(match) {
      ignore := contains(ignoreCVEs, match.Id)
      ignore
    }

    isCompliant = isSafe(input.currentVulnerability)

EOF
cat <<EOF > ootb-supply-chain-basic-values.yaml
grype:
  namespace: tap-install
  targetImagePullSecret: registry-credentials
EOF
cat <<EOF > tekton-pipeline.yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: developer-defined-tekton-pipeline
  labels:
    apps.tanzu.vmware.com/pipeline: test      # (!) required
spec:
  params:
    - name: source-url                        # (!) required
    - name: source-revision                   # (!) required
  tasks:
    - name: test
      params:
        - name: source-url
          value: $(params.source-url)
        - name: source-revision
          value: $(params.source-revision)
      taskSpec:
        params:
          - name: source-url
          - name: source-revision
        steps:
          - name: test
            image: gradle
            script: |-
              cd `mktemp -d`
              wget -qO- $(params.source-url) | tar xvz -m
              ./mvnw test
EOF
echo "############### Image Copy in progress  ##################"
echo "#################################"
imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:1.1.0 --to-repo $dockerhostname/tap-demo/tap-packages
tanzu package repository add tanzu-tap-repository --url $dockerhostname/tap-demo/tap-packages:1.1.0 --namespace tap-install
tanzu package repository get tanzu-tap-repository --namespace tap-install
tanzu package available list --namespace tap-install
echo "############### TAP 1.1.0 Install   ##################"
tanzu package install tap -p tap.tanzu.vmware.com -v 1.1.0 --values-file $HOME/tap-multi-cluster/tap-values-view.yaml -n tap-install
tanzu package installed list -A
reconcilestat=$(tanzu package installed list -A -o json | jq ' .[] | select(.status == "Reconcile failed: Error (see .status.usefulErrorMessage for details)" or .status == "Reconciling")' | jq length | awk '{sum=sum+$0} END{print sum}')
if [ $reconcilestat > '0' ];
  then
	tanzu package installed list -A
  echo "################# Wait for 10 minutes #################"
	sleep 10m
	tanzu package installed list -A
	tanzu package installed get tap -n tap-install
	reconcilestat1=$(tanzu package installed list -A -o json | jq ' .[] | select(.status == "Reconcile failed: Error (see .status.usefulErrorMessage for details)" or .status == "Reconciling")' | jq length | awk '{sum=sum+$0} END{print sum}')
	if [ $reconcilestat1 > '0' ];
	   then
		echo "################### Something is wrong with package install, Check the package status manually ############################"
		echo "################### Exiting #########################"
		exit
	else
		tanzu package installed list -A
		echo "################### Please check if all the packages are succeeded ############################"
		tanzu package installed get tap -n tap-install
	fi
else
	ip=$(kubectl get svc -n tap-gui -o=jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
fi
echo "####################################################################################"
echo "################### Change the context to Build cluster ############################"
echo "####################################################################################"
kubectl config get-contexts
kubectl config use-context tap-cluster-build
tanzu package repository add tanzu-tap-repository --url $dockerhostname/tap-demo/tap-packages:1.1.0 --namespace tap-install
tanzu package repository get tanzu-tap-repository --namespace tap-install
tanzu package available list --namespace tap-install
echo "############### TAP 1.1.0 Install   ##################"
tanzu package install tap -p tap.tanzu.vmware.com -v 1.1.0 --values-file $HOME/tap-multi-cluster/tap-values-build.yaml -n tap-install
tanzu package installed list -A
reconcilestat=$(tanzu package installed list -A -o json | jq ' .[] | select(.status == "Reconcile failed: Error (see .status.usefulErrorMessage for details)" or .status == "Reconciling")' | jq length | awk '{sum=sum+$0} END{print sum}')
if [ $reconcilestat > '0' ];
  then
  tanzu package installed list -A
  echo "################# Wait for 10 minutes #################"
  sleep 10m
  tanzu package installed list -A
  tanzu package installed get tap -n tap-install
  reconcilestat1=$(tanzu package installed list -A -o json | jq ' .[] | select(.status == "Reconcile failed: Error (see .status.usefulErrorMessage for details)" or .status == "Reconciling")' | jq length | awk '{sum=sum+$0} END{print sum}')
  if [ $reconcilestat1 > '0' ];
     then
    echo "################### Something is wrong with package install, Check the package status manually ############################"
    echo "################### Exiting #########################"
    exit
  else
    tanzu package installed list -A
    echo "################### Please check if all the packages are succeeded ############################"
    tanzu package installed get tap -n tap-install
  fi
else
  ip=$(kubectl get svc -n tap-gui -o=jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
fi
kubectl apply -f developer.yaml -n tap-install
kubectl apply -f tekton-pipeline.yaml -n tap-install
tanzu package install grype-scanner --package-name grype.scanning.apps.tanzu.vmware.com --version 1.1.0  --namespace tap-install -f ootb-supply-chain-basic-values.yaml
tanzu apps workload create tanzu-java-web-app  --git-repo https://github.com/Eknathreddy09/tanzu-java-web-app --git-branch main --type web --label apps.tanzu.vmware.com/has-tests=true --label app.kubernetes.io/part-of=tanzu-java-web-app  --type web -n tap-install --yes
tanzu apps workload get tanzu-java-web-app -n tap-install
echo "####################################################################################"
echo "################### Change the context to RUN cluster ############################"
echo "####################################################################################"
kubectl config get-contexts
kubectl config use-context tap-cluster-run
tanzu package repository add tanzu-tap-repository --url $dockerhostname/tap-demo/tap-packages:1.1.0 --namespace tap-install
tanzu package repository get tanzu-tap-repository --namespace tap-install
tanzu package available list --namespace tap-install
echo "############### TAP 1.1.0 Install   ##################"
tanzu package install tap -p tap.tanzu.vmware.com -v 1.1.0 --values-file $HOME/tap-multi-cluster/tap-values-run.yaml -n tap-install
tanzu package installed list -A
reconcilestat=$(tanzu package installed list -A -o json | jq ' .[] | select(.status == "Reconcile failed: Error (see .status.usefulErrorMessage for details)" or .status == "Reconciling")' | jq length | awk '{sum=sum+$0} END{print sum}')
if [ $reconcilestat > '0' ];
  then
  tanzu package installed list -A
  echo "################# Wait for 10 minutes #################"
  sleep 10m
  tanzu package installed list -A
  tanzu package installed get tap -n tap-install
  reconcilestat1=$(tanzu package installed list -A -o json | jq ' .[] | select(.status == "Reconcile failed: Error (see .status.usefulErrorMessage for details)" or .status == "Reconciling")' | jq length | awk '{sum=sum+$0} END{print sum}')
  if [ $reconcilestat1 > '0' ];
     then
    echo "################### Something is wrong with package install, Check the package status manually ############################"
    echo "################### Exiting #########################"
    exit
  else
    tanzu package installed list -A
    echo "################### Please check if all the packages are succeeded ############################"
    tanzu package installed get tap -n tap-install
  fi
else
  ip=$(kubectl get svc -n tap-gui -o=jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
fi
kubectl apply -f developer.yaml -n tap-install
echo "############## Get the package install status #################"
tanzu package installed get tap -n tap-install
tanzu package installed list -A

echo "####################################################################################"
echo "################### Change the context to Build cluster ############################"
echo "####################################################################################"
kubectl config get-contexts
kubectl config use-context tap-cluster-build
kubectl get deliverable tanzu-java-web-app --namespace $tap-install -oyaml > deliverable.yaml
yq 'del(.metadata."ownerReferences")' deliverable.yaml -i
yq 'del(."status")' deliverable.yaml -i

kubectl config get-contexts
kubectl config use-context tap-cluster-run

kubectl apply -f deliverable.yaml --namespace tap-install
kubectl get deliverables --namespace tap-install
echo "########################## Sleep time 3 mins - Go grab a Coffeee ###############################"
sleep 3m
kubectl get httpproxy --namespace tap-install
kubectl config get-contexts
kubectl config use-context tap-cluster-build
echo "################### Creating workload ##############################"
tanzu apps workload get tanzu-java-web-app -n tap-install
echo "#######################################################################"
echo "################ Monitor the progress #################################"
echo "#######################################################################"
tanzu apps workload tail tanzu-java-web-app --since 10m --timestamp -n tap-install
