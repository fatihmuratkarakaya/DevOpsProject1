#!/bin/bash

# Color for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Source secrets reference
source $(dirname "$0")/secrets-reference.sh

# Redis connection details
REDIS_HOST="localhost"
REDIS_PORT="30002"

# Get password from Kubernetes secret
REDIS_PASS=$(kubectl get secret -n redis $REDIS_SECRET_NAME -o jsonpath="{.data.$REDIS_SECRET_KEY}" | base64 --decode)

echo "Checking Redis setup..."
echo "============================"
echo "Connection details:"
echo "  Host: $REDIS_HOST"
echo "  Port: $REDIS_PORT"
echo "  Password: ********" # Don't print the actual password
echo "============================"

# Check if Redis CLI is installed
if ! command -v redis-cli &> /dev/null; then
    echo -e "${YELLOW}Redis CLI not found. Installing...${NC}"
    sudo apt-get update && sudo apt-get install -y redis-tools
fi

# Create a temporary Redis configuration file
REDIS_CONF=$(mktemp)
echo "requirepass $REDIS_PASS" > $REDIS_CONF

# Helper function to run Redis commands without password warning
redis_cmd() {
    redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASS --no-auth-warning "$@"
}

# Check if Redis pods are running
echo "Checking if Redis is running in Kubernetes..."
if kubectl get pods -n redis | grep -q "Running"; then
    echo -e "${GREEN}Redis pods are running.${NC}"
else
    echo -e "${RED}Redis pods are not running. Please check your installation.${NC}"
    exit 1
fi

# Test 1: Basic connectivity test
echo -e "\n${YELLOW}Test 1: Testing basic connectivity to Redis...${NC}"
if redis_cmd PING | grep -q "PONG"; then
    echo -e "${GREEN}✓ Connection test passed! Redis server is responsive.${NC}"
else
    echo -e "${RED}✗ Connection test failed. Cannot connect to Redis server.${NC}"
    exit 1
fi

# Test 2: SET and GET operations
echo -e "\n${YELLOW}Test 2: Testing basic SET and GET operations...${NC}"
TEST_KEY="test:$(date +%s)"
TEST_VALUE="Hello from $(hostname) at $(date)"

if redis_cmd SET $TEST_KEY "$TEST_VALUE" | grep -q "OK"; then
    echo -e "${GREEN}✓ SET operation successful.${NC}"
    
    RETRIEVED_VALUE=$(redis_cmd GET $TEST_KEY)
    if [ "$RETRIEVED_VALUE" == "$TEST_VALUE" ]; then
        echo -e "${GREEN}✓ GET operation successful. Retrieved value matches.${NC}"
    else
        echo -e "${RED}✗ GET operation failed. Retrieved value doesn't match.${NC}"
        echo "  Expected: $TEST_VALUE"
        echo "  Got: $RETRIEVED_VALUE"
        exit 1
    fi
else
    echo -e "${RED}✗ SET operation failed.${NC}"
    exit 1
fi

# Test 3: Data persistence
echo -e "\n${YELLOW}Test 3: Testing data persistence...${NC}"
PERSISTENCE_KEY="persistent:$(date +%s)"
PERSISTENCE_VALUE="This value should persist"

redis_cmd SET $PERSISTENCE_KEY "$PERSISTENCE_VALUE" > /dev/null
redis_cmd SAVE > /dev/null

echo "SET operation completed and SAVE command issued."
echo "Value should be persisted to disk now."

# We would need to restart Redis to fully test persistence,
# but we don't want to do that in a production environment
echo -e "${GREEN}✓ Persistence check completed. For a full test, Redis would need to be restarted.${NC}"

# Test 4: Caching behavior
echo -e "\n${YELLOW}Test 4: Testing caching behavior with expiry...${NC}"
CACHE_KEY="cache:$(date +%s)"
CACHE_VALUE="This value will expire in 10 seconds"

redis_cmd SETEX $CACHE_KEY 10 "$CACHE_VALUE" > /dev/null
echo "Set $CACHE_KEY with 10 second expiry"

RETRIEVED_CACHE=$(redis_cmd GET $CACHE_KEY)
if [ "$RETRIEVED_CACHE" == "$CACHE_VALUE" ]; then
    echo -e "${GREEN}✓ Cache value retrieved successfully before expiry.${NC}"
    
    echo "Waiting for cache to expire (10 seconds)..."
    sleep 11
    
    EXPIRED_CACHE=$(redis_cmd GET $CACHE_KEY)
    if [ -z "$EXPIRED_CACHE" ]; then
        echo -e "${GREEN}✓ Cache expired as expected.${NC}"
    else
        echo -e "${RED}✗ Cache did not expire as expected.${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Failed to retrieve cache value.${NC}"
    exit 1
fi

# Test 5: Performance test (optional)
echo -e "\n${YELLOW}Test 5: Running a small performance test...${NC}"
echo "Inserting 1000 keys..."
for i in {1..1000}; do
    redis_cmd SET "perf:$i" "value-$i" > /dev/null
done

START_TIME=$(date +%s%N)
redis_cmd GET "perf:500" > /dev/null
END_TIME=$(date +%s%N)

ELAPSED_TIME=$((($END_TIME - $START_TIME) / 1000000))
echo -e "${GREEN}✓ Read operation took $ELAPSED_TIME ms.${NC}"

echo -e "\n${GREEN}Redis is working properly and configured for caching!${NC}"
echo -e "${GREEN}All tests passed successfully.${NC}"

# Clean up test keys
echo -e "\n${YELLOW}Cleaning up test keys...${NC}"
redis_cmd DEL $TEST_KEY $PERSISTENCE_KEY > /dev/null
for i in {1..1000}; do
    redis_cmd DEL "perf:$i" > /dev/null
done
echo -e "${GREEN}Cleanup completed.${NC}"

# Remove temporary file
rm $REDIS_CONF