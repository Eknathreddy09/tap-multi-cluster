#!/bin/bash
echo "############################ Keep these values handy:   ######################"
echo "############################ Pivnet token, Tanzu network username  ######################"
echo "############################ Tanzu network password, Ingress Domain for CNRS   ######################"
echo "############################ domain name for Learning center, region to deploy AKS Cluster and ACR repo  ######################"
echo "############################ github token, Subscription ID   ######################"
echo "#####################################################################################################"
echo "##### Pivnet Token: login to tanzu network, click on your username in top right corner of the page > select Edit Profile, scroll down and click on Request New Refresh Token ######"
read -p "Enter the Pivnet token: " pivnettoken
read -p "Enter the Tanzu network username: " tanzunetusername
read -p "Enter the Tanzu network password: " tanzunetpassword
read -p "Enter the Ingress Domain for CNRS: " cnrsdomain
read -p "Enter the domain name for Learning center: " domainname
read -p "Enter github token (to be collected from Githubportal): " githubtoken
read -p "Do you want to use existing AKS cluster or create a new one? Type "N" for new, "E" for existing: " clusterconnect
read -p "Do you want to use existing ACR repo or create a new one? Type "N" for new, "E" for existing: " azurerepo
read -p "Do you want to use existing EKS cluster or create a new one? Type "N" for new, "E" for existing: " clusterconnecteks
read -p "Enter the Subscription ID: " subscription
echo "#################  Installing AZ cli #####################"
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
sudo apt-get install jq -y
sudo snap install yq
echo "#########################################"
echo "################ AZ CLI version #####################"
az --version
echo "#########################################"
echo "#########################################"
echo "#########################################"
echo "Installing AWS cli"
echo "#########################################"
echo "#########################################"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip
unzip awscliv2.zip
sudo ./aws/install
./aws/install -i /usr/local/aws-cli -b /usr/local/bin
echo "#########################################"
echo "AWS CLI version"
echo "#########################################"
aws --version
echo "#########################################"
echo "############# Provide AWS access key and secrets  ##########################"
aws configure
read -p "Enter AWS session token: " aws_token
aws configure set aws_session_token $aws_token
echo "############### Install kubectl ##############"
sudo az aks install-cli
echo "############  Kubectl Version #######################"
kubectl version
echo "#####################################################################################################"
echo "#############  Authenticate to AZ cli by following the screen Instructions below #################"
echo "#####################################################################################################"
az login
echo "#########################################"
echo "#########################################"
echo "############# Installing Pivnet ###########"
wget https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1
chmod +x pivnet-linux-amd64-3.0.1
sudo mv pivnet-linux-amd64-3.0.1 /usr/local/bin/pivnet
pivnet login --api-token=${pivnettoken}
pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.1.0' --product-file-id=1191987
mkdir $HOME/tanzu-cluster-essentials
tar -xvf tanzu-cluster-essentials-linux-amd64-1.1.0.tgz -C $HOME/tanzu-cluster-essentials
export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:ab0a3539da241a6ea59c75c0743e9058511d7c56312ea3906178ec0f3491f51d
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$tanzunetusername
export INSTALL_REGISTRY_PASSWORD=$tanzunetpassword
if [ "$azurerepo" == "E" ];
then
    echo "###### Provide existing ACR details  ######"
    read -p "Enter ACR Login server Name: " acrloginserver
    read -p "Enter ACR Login server username: " acrusername
    read -p "Enter ACR Login server password: " acrpassword
else
     read -p "Enter the region to create ACR  : " regionacr
     echo "###### Create RG for Repo  ######"
     az group create --name tap-imagerepo-RG --location $regionacr
     echo "####### Create container registry  ############"
         echo "#####################################################################################################"
     az acr create --resource-group tap-imagerepo-RG --name tapdemoacr --sku Standard
     echo "####### Fetching acr Admin credentials ##########"
     az acr update -n tapdemoacr --admin-enabled true
         acrusername=$(az acr credential show --name tapdemoacr --query "username" -o tsv)
         acrloginserver=$(az acr show --name tapdemoacr --query loginServer -o tsv)
         acrpassword=$(az acr credential show --name tapdemoacr --query passwords[0].value -o tsv)
         if grep -q "/"  <<< "$acrpassword";
             then
            acrpassword1=$(az acr credential show --name tapdemoacr --query passwords[1].value -o tsv)
            if grep -q "/"  <<< "$acrpassword1";
              then
                       echo "##########################################################################"
               echo "Update the password manually in tap-values file(repopassword): password is $acrpassword1 "
                       echo "###########################################################################"
            else
           acrpassword=$acrpassword1
            fi
         else
              echo "Password Updated in tap values file"
         fi

fi
if [ "$clusterconnect" == "N" ];
then
     read -p "Enter the region to deploy AKS Cluster: " regionaks
     echo "#########################################"
         echo "Resource group created with name tap-cluster-RG in region and subscription mentioned above"
         echo "#########################################"
     az group create --name tap-cluster-RG --location $regionaks --subscription $subscription
         echo "#########################################"
     echo "Creating AKS cluster with 1 node and sku as Standard_D8S_v3, can be changed if required"
         echo "#########################################"
         az aks create --resource-group tap-cluster-RG --name tap-cluster-build --subscription $subscription --node-count 1 --enable-addons monitoring --generate-ssh-keys --node-vm-size Standard_D8S_v3 -z 1 --enable-cluster-autoscaler --min-count 1 --max-count 1
         az aks create --resource-group tap-cluster-RG --name tap-cluster-run --subscription $subscription --node-count 1 --enable-addons monitoring --generate-ssh-keys --node-vm-size Standard_D8S_v3 -z 1 --enable-cluster-autoscaler --min-count 1 --max-count 1

         echo "############### Created AKS Cluster ###############"
     echo "############### Set the context ###############"
     az account set --subscription $subscription
     az aks get-credentials --resource-group tap-cluster-RG --name tap-cluster-build
     echo "############## Verify the nodes #################"
     echo "#####################################################################################################"
     kubectl get nodes
         echo "#####################################################################################################"
else
        az account set --subscription $subscription
        read -p "Provide the AKS cluster resource group: " aksclusterresourcegroup
        read -p "Provide the AKS cluster name: " aksclustername
        az aks get-credentials --resource-group aksclusterresourcegroup --name aksclustername
fi
cat <<EOF > tap-gui-viewer-service-account-rbac.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tap-gui
---
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: tap-gui
  name: tap-gui-viewer
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tap-gui-read-k8s
subjects:
- kind: ServiceAccount
  namespace: tap-gui
  name: tap-gui-viewer
roleRef:
  kind: ClusterRole
  name: k8s-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-reader
rules:
- apiGroups: ['']
  resources: ['pods', 'services', 'configmaps']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['apps']
  resources: ['deployments', 'replicasets']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['autoscaling']
  resources: ['horizontalpodautoscalers']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['networking.k8s.io']
  resources: ['ingresses']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['networking.internal.knative.dev']
  resources: ['serverlessservices']
  verbs: ['get', 'watch', 'list']
- apiGroups: [ 'autoscaling.internal.knative.dev' ]
  resources: [ 'podautoscalers' ]
  verbs: [ 'get', 'watch', 'list' ]
- apiGroups: ['serving.knative.dev']
  resources:
  - configurations
  - revisions
  - routes
  - services
  verbs: ['get', 'watch', 'list']
- apiGroups: ['carto.run']
  resources:
  - clusterconfigtemplates
  - clusterdeliveries
  - clusterdeploymenttemplates
  - clusterimagetemplates
  - clusterruntemplates
  - clustersourcetemplates
  - clustersupplychains
  - clustertemplates
  - deliverables
  - runnables
  - workloads
  verbs: ['get', 'watch', 'list']
- apiGroups: ['source.toolkit.fluxcd.io']
  resources:
  - gitrepositories
  verbs: ['get', 'watch', 'list']
- apiGroups: ['source.apps.tanzu.vmware.com']
  resources:
  - imagerepositories
  verbs: ['get', 'watch', 'list']
- apiGroups: ['conventions.apps.tanzu.vmware.com']
  resources:
  - podintents
  verbs: ['get', 'watch', 'list']
- apiGroups: ['kpack.io']
  resources:
  - images
  - builds
  verbs: ['get', 'watch', 'list']
- apiGroups: ['scanning.apps.tanzu.vmware.com']
  resources:
  - sourcescans
  - imagescans
  verbs: ['get', 'watch', 'list']
- apiGroups: ['tekton.dev']
  resources:
  - taskruns
  - pipelineruns
  verbs: ['get', 'watch', 'list']
- apiGroups: ['kappctrl.k14s.io']
  resources:
  - apps
  verbs: ['get', 'watch', 'list']
EOF
kubectl config get-contexts
kubectl create ns tap-install
kubectl create -f /home/azureuser/multi-cluster/tap-gui-viewer-service-account-rbac.yaml
CLUSTER_URL_BUILD=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_TOKEN_BUILD=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json | jq -r '.secrets[0].name') -o=json | jq -r '.data["token"]' | base64 --decode)
cd $HOME/tanzu-cluster-essentials
./install.sh -y
az aks get-credentials --resource-group tap-cluster-RG --name tap-cluster-run
kubectl config get-contexts
kubectl create ns tap-install
kubectl create -f /home/azureuser/multi-cluster/tap-gui-viewer-service-account-rbac.yaml
CLUSTER_URL_RUN=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_TOKEN_RUN=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json | jq -r '.secrets[0].name') -o=json | jq -r '.data["token"]' | base64 --decode)
cd $HOME/tanzu-cluster-essentials
./install.sh -y
cd /home/azureuser/multi-cluster
echo "######### Preparing the tap-values Build file ##########"
cat <<EOF > tap-values-build.yaml
profile: build
ceip_policy_disclosed: true # Installation fails if this is set to 'false'
buildservice:
  kp_default_repository: "$dockerhostname/build-service" # Replace the project id with yours. In my case eknath-se is the project ID
  kp_default_repository_username: $dockerusername
  kp_default_repository_password: $dockerpassword
  tanzunet_username: "$tanzunetusername" # Provide the Tanzu network user name
  tanzunet_password: "$tanzunetpassword" # Provide the Tanzu network password
supply_chain: testing_scanning
ootb_supply_chain_testing_scanning:
  registry:
    server: "$dockerhostname"
    repository: "supply-chain" # Replace the project id with yours. In my case eknath-se is the project ID
  gitops:
    ssh_secret: ""
  cluster_builder: default
  service_account: default
grype:
  namespace: "tap-install" # (optional) Defaults to default namespace.
  targetImagePullSecret: "registry-credentials"
EOF
echo "######### Preparing the tap-values Run file ##########"
cat <<EOF > tap-values-run.yaml
profile: run
ceip_policy_disclosed: true # Installation fails if this is set to 'false'
supply_chain: testing_scanning
ootb_supply_chain_testing_scanning:
  registry:
    server: "$dockerhostname"
    repository: "supply-chain" # Replace the project id with yours. In my case eknath-se is the project ID
cnrs:
  domain_name: $cnrsdomain

contour:
  envoy:
    service:
      type: LoadBalancer

appliveview_connector:
  backend:
    sslDisabled: true
    host: "appliveview.$cnrsdomain"
EOF
echo "######### Preparing the tap-values View file ##########"
cat <<EOF > tap-values-view.yaml
profile: view
ceip_policy_disclosed: true # Installation fails if this is set to 'false'
learningcenter:
  ingressDomain: "$domainname" # Provide a Domain Name
contour:
  envoy:
    service:
      type: LoadBalancer
metadata_store:
  app_service_type: LoadBalancer # (optional) Defaults to LoadBalancer. Change to NodePort for distributions that don't support LoadBalancer
tap_gui:
  service_type: LoadBalancer # NodePort for distributions that don't support LoadBalancer
  app_config:
    app:
      baseUrl: http://tap-gui.$cnrsdomain
    integrations:
      github: # Other integrations available see NOTE below
        - host: github.com
          token: $githubtoken  # Create a token in github
    catalog:
      locations:
        - type: url
          target: https://github.com/Eknathreddy09/tanzu-java-web-app/blob/main/catalog/catalog-info.yaml
    backend:
      baseUrl: http://tap-gui.$cnrsdomain
      cors:
        origin: http://tap-gui.$cnrsdomain
    kubernetes:
      serviceLocatorMethod:
        type: 'multiTenant'
      clusterLocatorMethods:
        - type: 'config'
          clusters:
            - url: $CLUSTER_URL_BUILD
              name: tap-cluster-build
              authProvider: serviceAccount
              serviceAccountToken: $CLUSTER_TOKEN_BUILD
              skipTLSVerify: true
            - url:
              name: $CLUSTER_URL_RUN
              authProvider: serviceAccount
              serviceAccountToken: $CLUSTER_TOKEN_RUN
              skipTLSVerify: true
appliveview:
  ingressEnabled: true
  ingressDomain: appliveview.$cnrsdomain
EOF
echo "#####################################################################################################"
if [ "$clusterconnecteks" == "N" ];
then
    read -p "Enter the region to deploy EKS: " region

echo "################## Creating IAM Roles for EKS Cluster and nodes ###################### "
cat <<EOF > cluster-role-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
cat <<EOF > node-role-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
aws iam create-role --role-name tap-EKSClusterRole --assume-role-policy-document file://"cluster-role-trust-policy.json"
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name tap-EKSClusterRole
aws iam create-role --role-name tap-EKSNodeRole --assume-role-policy-document file://"node-role-trust-policy.json"
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name tap-EKSNodeRole
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name tap-EKSNodeRole
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --role-name tap-EKSNodeRole

echo "########################### Creating VPC Stacks through cloud formation ##############################"
aws cloudformation create-stack --region $region --stack-name tap-demo-vpc-stack --template-url https://amazon-eks.s3.us-west-2.amazonaws.com/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml
echo "############## Waiting for VPC stack to get created ###################"
echo "############## Paused for 5 mins ##########################"
sleep 5m
pubsubnet1=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=tap-demo-vpc-stack-PublicSubnet01 --query Subnets[0].SubnetId --output text)
pubsubnet2=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=tap-demo-vpc-stack-PublicSubnet02 --query Subnets[0].SubnetId --output text)
rolearn=$(aws iam get-role --role-name tap-EKSClusterRole --query Role.Arn --output text)
sgid=$(aws ec2 describe-security-groups --filters Name=description,Values="Cluster communication with worker nodes" --query SecurityGroups[0].GroupId --output text)

echo "########################## Creating EKS Cluster ########################################"

ekscreatecluster=$(aws eks create-cluster --region $region --name tapdemo-eks-view --kubernetes-version 1.21 --role-arn $rolearn --resources-vpc-config subnetIds=$pubsubnet1,$pubsubnet2,securityGroupIds=$sgid)

echo "############## Waiting for EKS cluster to get created ###################"
echo "############## Paused for 15 mins ###############################"
sleep 15m
aws eks update-kubeconfig --region $region --name tapdemo-eks-view

rolenodearn=$(aws iam get-role --role-name tap-EKSNodeRole --query Role.Arn --output text)
echo "######################### Creating Node Group ###########################"
aws eks create-nodegroup --cluster-name tapdemo-eks-view --nodegroup-name tapdemo-eks-viewng --node-role $rolenodearn --instance-types t2.2xlarge --scaling-config minSize=1,maxSize=1,desiredSize=1 --disk-size 40  --subnets $pubsubnet1

echo "############## Waiting for Node groups to get created ###################"
echo "############### Paused for 10 mins ################################"
sleep 10m

else
        read -p "Provide the EKS cluster : " eksclustername
        read -p "Provide the EKS cluster region: " eksclusterregion
        aws eks update-kubeconfig --region $eksclusterregion --name $eksclustername
fi
cd $HOME/tanzu-cluster-essentials
./install.sh
        echo "########### Creating Secrets in tap-install namespace  #############"
        kubectl create ns tap-install
        kubectl create secret docker-registry registry-credentials --docker-server=$acrloginserver --docker-username=$acrusername --docker-password=$acrpassword -n tap-install

echo "######## Installing Kapp ###########"
sudo cp $HOME/tanzu-cluster-essentials/kapp /usr/local/bin/kapp
kapp version
echo "######## Installing Imgpkg ###########"
sudo cp $HOME/tanzu-cluster-essentials/imgpkg /usr/local/bin/imgpkg
imgpkg version
echo "#################################"
pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.1.0' --product-file-id=1190781
mkdir $HOME/tanzu
tar -xvf tanzu-framework-linux-amd64.tar -C $HOME/tanzu
export TANZU_CLI_NO_INIT=true
cd $HOME/tanzu
sudo install cli/core/v0.11.2/tanzu-core-linux_amd64 /usr/local/bin/tanzu
tanzu version
tanzu plugin install --local cli all
tanzu plugin list
echo "######### Installing Docker ############"
sudo apt-get update
sudo apt-get install  ca-certificates curl  gnupg  lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io -y
sudo usermod -aG docker $USER
echo "####### Install tap-registry in all namespaces  ###########"
echo "#####################################################################################################"
echo "########### Rebooting #############"
sudo reboot
