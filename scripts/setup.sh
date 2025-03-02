#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Kubernetes Environment Setup...${NC}"

# Step 1: Install dependencies
echo -e "${GREEN}Installing dependencies...${NC}"
chmod +x ./scripts/install_dependencies.sh
./scripts/install_dependencies.sh

# Step 2: Set up KIND cluster using Terraform
echo -e "${GREEN}Setting up KIND cluster with Terraform...${NC}"
cd terraform
terraform init
terraform apply -auto-approve
cd ..

# Step 3: Configure kubectl to use the new cluster
echo -e "${GREEN}Configuring kubectl...${NC}"
mkdir -p $HOME/.kube
kind get kubeconfig --name=jenkins-postgres-cluster > $HOME/.kube/config

# Step 4: Set up RBAC for Jenkins
echo -e "${GREEN}Setting up RBAC for Jenkins...${NC}"
kubectl create namespace jenkins

# Create a ClusterRoleBinding for the Jenkins service account
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-cluster-admin
subjects:
- kind: ServiceAccount
  name: jenkins
  namespace: jenkins
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF


# Generate random passwords
echo -e "${GREEN}Setting up secrets for databases...${NC}"
POSTGRES_PASSWORD=$(openssl rand -base64 16)
REDIS_PASSWORD=$(openssl rand -base64 16)

# Create namespaces
kubectl create namespace postgresql --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace redis --dry-run=client -o yaml | kubectl apply -f -

# Create secrets
kubectl create secret generic postgresql-secret \
  --namespace postgresql \
  --from-literal=postgres-password=$POSTGRES_PASSWORD

kubectl create secret generic redis-secret \
  --namespace redis \
  --from-literal=redis-password=$REDIS_PASSWORD

# Store a reference to secrets for check scripts
cat > scripts/secrets-reference.sh << EOF
#!/bin/bash
# Reference file for accessing secrets
# Do not store actual passwords here
POSTGRES_SECRET_NAME="postgresql-secret"
POSTGRES_SECRET_KEY="postgres-password"
REDIS_SECRET_NAME="redis-secret"
REDIS_SECRET_KEY="redis-password"
EOF
chmod +x scripts/secrets-reference.sh



# Step 5: Install Jenkins using Helm
echo -e "${GREEN}Installing Jenkins...${NC}"
helm repo add jenkinsci https://charts.jenkins.io
helm repo update
helm install jenkins jenkinsci/jenkins -f helm/jenkins-values.yaml -n jenkins

# Step 6: Wait for Jenkins to be ready
echo -e "${GREEN}Waiting for Jenkins to be ready...${NC}"
kubectl rollout status statefulset/jenkins -n jenkins

# Step 7: Get Jenkins admin password and provide access information
echo -e "${GREEN}Retrieving Jenkins admin credentials...${NC}"
JENKINS_PASS=$(kubectl exec -n jenkins jenkins-0 -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password 2>/dev/null || echo "admin")
JENKINS_PORT=30000

echo -e "${BLUE}====================${NC}"
echo -e "${BLUE}Setup Complete!${NC}"
echo -e "${BLUE}Jenkins URL: http://localhost:$JENKINS_PORT${NC}"
echo -e "${BLUE}Jenkins Admin Username: admin${NC}"
echo -e "${BLUE}Jenkins Admin Password: $JENKINS_PASS${NC}"
echo -e "${BLUE}====================${NC}"
echo -e "${BLUE}Jenkins will automatically create the following pipelines:${NC}"
echo -e "${BLUE}1. PostgreSQL deployment: http://localhost:$JENKINS_PORT/job/postgresql-deployment/${NC}"
echo -e "${BLUE}2. Redis deployment: http://localhost:$JENKINS_PORT/job/redis-deployment/${NC}"
echo -e "${BLUE}====================${NC}"
echo -e "${BLUE}After deployment, you can verify your databases:${NC}"
echo -e "${BLUE}- PostgreSQL: ./scripts/check_postgresql.sh${NC}"
echo -e "${BLUE}  Available at: localhost:30001 (user: postgres, password: postgres)${NC}"
echo -e "${BLUE}- Redis: ./scripts/check_redis.sh${NC}"
echo -e "${BLUE}  Available at: localhost:30002 (password: redis)${NC}"
echo -e "${BLUE}====================${NC}"