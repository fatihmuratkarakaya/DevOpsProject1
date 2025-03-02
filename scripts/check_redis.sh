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

# Get password from Kubernetes secret
POSTGRES_PASSWORD=$(kubectl get secret -n postgresql $POSTGRES_SECRET_NAME -o jsonpath="{.data.$POSTGRES_SECRET_KEY}" | base64 --decode)

echo "Checking PostgreSQL setup..."
echo "============================"
echo "Connection details:"
echo "  Host: $NODE_IP"
echo "  Port: $POSTGRES_PORT"
echo "  User: $POSTGRES_USER"
echo "  Database: $POSTGRES_DB"
echo "  Password: ********" # Don't print the actual password
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
  if nc -z -v -w5 $NODE_IP $POSTGRES_PORT 2>&1; then
    echo -e "${GREEN}Port is open and accessible.${NC}"
  else
    echo -e "${RED}Cannot connect to $NODE_IP:$POSTGRES_PORT - port may be closed.${NC}"
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
psql -c "SELECT version();" || {
  echo -e "${RED}Failed to connect to PostgreSQL.${NC}"
  echo "Let's try to access PostgreSQL from inside the cluster using kubectl..."
  
  POSTGRES_POD=$(kubectl get pods -n postgresql -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')
  echo "PostgreSQL pod: $POSTGRES_POD"
  
  echo "Testing database connectivity from within the pod..."
  kubectl exec -n postgresql $POSTGRES_POD -- bash -c "PGPASSWORD=postgres psql -U postgres -c 'SELECT version();'"
  
  echo -e "${RED}The database is accessible from inside the cluster but not from outside.${NC}"
  echo -e "${RED}This may be due to network policies or incorrect NodePort configuration.${NC}"
  
  exit 1
}

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
    ('John Smith', 'Software Engineer', 'Engineering', 85000.00, '2020-05-15'),
    ('Jane Doe', 'Product Manager', 'Product', 95000.00, '2019-03-20'),
    ('Michael Johnson', 'UX Designer', 'Design', 75000.00, '2021-01-10'),
    ('Emily Williams', 'Data Scientist', 'Analytics', 90000.00, '2018-11-05'),
    ('Robert Brown', 'DevOps Engineer', 'Operations', 88000.00, '2020-08-15');

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