#!/bin/bash

# Color for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Source secrets reference
source $(dirname "$0")/secrets-reference.sh

# PostgreSQL connection details
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
POSTGRES_PORT=30001
POSTGRES_USER="postgres"
POSTGRES_DB="postgres"

# Check if PostgreSQL client is installed
if ! command -v psql &> /dev/null; then
    echo -e "${YELLOW}PostgreSQL client not found. Installing...${NC}"
    sudo apt-get update && sudo apt-get install -y postgresql-client
    
    if ! command -v psql &> /dev/null; then
        echo -e "${RED}Failed to install PostgreSQL client. Please install it manually:${NC}"
        echo "sudo apt-get install postgresql-client"
        exit 1
    fi
fi

# Get base64 decode option that works on this system
BASE64_DECODE_OPT=$(base64 --help 2>&1 | grep -q "\-\-decode" && echo "--decode" || echo "-d")

# Get password from Kubernetes secret
echo "Retrieving PostgreSQL password from secret..."
POSTGRES_PASSWORD=$(kubectl get secret -n postgresql $POSTGRES_SECRET_NAME -o jsonpath="{.data.$POSTGRES_SECRET_KEY}" | base64 $BASE64_DECODE_OPT)

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo -e "${RED}Failed to retrieve password from secret.${NC}"
  echo "Checking secret existence and key name..."
  kubectl get secret -n postgresql $POSTGRES_SECRET_NAME -o yaml
  echo -e "${YELLOW}Using default password as fallback.${NC}"
  POSTGRES_PASSWORD="postgres"
fi

echo "Checking PostgreSQL setup..."
echo "============================"
echo "Connection details:"
echo "  Host: $NODE_IP"
echo "  Port: $POSTGRES_PORT"
echo "  User: $POSTGRES_USER"
echo "  Database: $POSTGRES_DB"
echo "  Password: ********"
echo "============================"

# Check if PostgreSQL is running
echo "Checking if PostgreSQL is running..."
POSTGRES_PODS=$(kubectl get pods -n postgresql -o jsonpath='{.items[*].metadata.name}')
echo "PostgreSQL pods: $POSTGRES_PODS"

if kubectl get pods -n postgresql | grep -q "Running"; then
  echo -e "${GREEN}PostgreSQL pods are running.${NC}"
else
  echo -e "${RED}PostgreSQL pods are not running. Please check your installation.${NC}"
  exit 1
fi

# Test the connection with nc (netcat) if available
if command -v nc &> /dev/null; then
  echo "Testing connection with netcat..."
  if nc -z -v -w5 localhost $POSTGRES_PORT 2>&1; then
    echo -e "${GREEN}Port is open and accessible.${NC}"
  else
    echo -e "${RED}Cannot connect to localhost:$POSTGRES_PORT - port may be closed.${NC}"
    echo "Trying with $NODE_IP instead..."
    if nc -z -v -w5 $NODE_IP $POSTGRES_PORT 2>&1; then
      echo -e "${GREEN}Port is open and accessible on $NODE_IP.${NC}"
    else
      echo -e "${RED}Cannot connect to $NODE_IP:$POSTGRES_PORT - port may be closed.${NC}"
    fi
  fi
fi

# Create a sample table and insert data
echo "Creating a sample table and inserting dummy data..."

# Use environment variables for PostgreSQL connection
export PGPASSWORD=$POSTGRES_PASSWORD
export PGHOST="localhost"
export PGPORT=$POSTGRES_PORT
export PGUSER=$POSTGRES_USER
export PGDATABASE=$POSTGRES_DB

echo "Attempting to connect to PostgreSQL with: psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE"

# Try psql with -c to test connection
if ! psql -c "SELECT version();"; then
  echo -e "${RED}Failed to connect to PostgreSQL with localhost.${NC}"
  echo "Trying with node IP instead..."
  
  export PGHOST=$NODE_IP
  if ! psql -c "SELECT version();"; then
    echo -e "${RED}Failed to connect to PostgreSQL.${NC}"
    echo "Let's try to access PostgreSQL from inside the cluster using kubectl..."
    
    POSTGRES_POD=$(kubectl get pods -n postgresql -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POSTGRES_POD" ]; then
      POSTGRES_POD=$(kubectl get pods -n postgresql -o jsonpath='{.items[0].metadata.name}')
    fi
    echo "PostgreSQL pod: $POSTGRES_POD"
    
    echo "Getting the actual password from inside the pod..."
    POD_PASSWORD=$(kubectl exec -n postgresql $POSTGRES_POD -- bash -c "echo \$POSTGRES_PASSWORD" 2>/dev/null || echo "")
    
    if [ -n "$POD_PASSWORD" ]; then
      echo -e "${YELLOW}Using password from inside the pod.${NC}"
      PGPASSWORD=$POD_PASSWORD
    fi
    
    echo "Testing database connectivity from within the pod..."
    kubectl exec -n postgresql $POSTGRES_POD -- bash -c "PGPASSWORD=$PGPASSWORD psql -U postgres -c 'SELECT version();'" || true
    
    echo -e "${RED}The database might not be accessible from outside the cluster.${NC}"
    echo -e "${RED}This may be due to network policies or incorrect NodePort configuration.${NC}"
    
    exit 1
  fi
fi

psql << EOF
-- Check if table exists and drop it if it does
DROP TABLE IF EXISTS employees;

-- Create a sample table
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    position VARCHAR(100),
    department VARCHAR(100),
    salary NUMERIC(10,2),
    hire_date DATE
);

-- Insert dummy data
INSERT INTO employees (name, position, department, salary, hire_date)
VALUES 
    ('John Smith', 'Software Engineer', 'Engineering', 95000.00, '2020-05-15'),
    ('Jane Doe', 'Product Manager', 'Product', 115000.00, '2019-03-20'),
    ('Michael Johnson', 'UX Designer', 'Design', 105000.00, '2021-01-10'),
    ('Emily Williams', 'Data Scientist', 'Analytics', 100000.00, '2018-11-05'),
    ('Robert Brown', 'DevOps Engineer', 'Operations', 98000.00, '2020-08-15');

-- Retrieve the data to verify
SELECT * FROM employees;
EOF

if [ $? -eq 0 ]; then
  echo -e "${GREEN}Success! PostgreSQL is working properly.${NC}"
  echo -e "${GREEN}Created 'employees' table with sample data.${NC}"
  
  # Run a separate query to show the data nicely
  echo "Fetching data from the employees table:"
  psql -c "SELECT * FROM employees;"
  
  echo -e "${GREEN}PostgreSQL is properly set up and operational!${NC}"
else
  echo -e "${RED}Failed to create sample data. Please check your PostgreSQL installation.${NC}"
  exit 1
fi