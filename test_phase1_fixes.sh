#!/bin/bash
# Test script for Phase 1 reliability fixes
# Tests: timestamp, threshold notification, duplicate seed fetch, seed failure handling

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/test_temp"
ERRORS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Phase 1 Fixes Test Suite"
echo "========================================="

# Setup test environment
setup_test_env() {
    echo -e "\n${YELLOW}[SETUP]${NC} Creating test environment..."
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"

    # Create a test config file
    cat > "$TEST_DIR/probe_nodes_conf.json" <<EOF
{
    "CONFIG_DIR": "$TEST_DIR",
    "SEED_NODES_URL": "http://fake-url.test/nodes",
    "MAX_ALERTS": 3,
    "THRESHOLD": 5,
    "POCKETCOIN_CLI_ARGS": "-testnet",
    "RECIPIENT_EMAIL": "test@example.com",
    "EMAIL_TESTING": "false",
    "MAJORITY_LAG_THRESH": 10
}
EOF

    echo -e "${GREEN}[PASS]${NC} Test environment created"
}

# Test 1: Verify timestamp variable is defined
test_timestamp_defined() {
    echo -e "\n${YELLOW}[TEST 1]${NC} Checking timestamp variable definition..."

    if grep -q '^    local timestamp=' "$SCRIPT_DIR/probe_nodes.sh"; then
        echo -e "${GREEN}[PASS]${NC} Timestamp variable is defined in main function"
    else
        echo -e "${RED}[FAIL]${NC} Timestamp variable not found"
        ((ERRORS++))
    fi
}

# Test 2: Verify threshold notification type exists
test_threshold_notification() {
    echo -e "\n${YELLOW}[TEST 2]${NC} Checking threshold notification type..."

    if grep -q '"offline"|"threshold"' "$SCRIPT_DIR/probe_nodes.sh"; then
        echo -e "${GREEN}[PASS]${NC} Threshold notification type is defined"
    else
        echo -e "${RED}[FAIL]${NC} Threshold notification type not found"
        ((ERRORS++))
    fi
}

# Test 3: Verify no duplicate seed node fetching
test_no_duplicate_fetch() {
    echo -e "\n${YELLOW}[TEST 3]${NC} Checking for duplicate seed node fetching..."

    # Count how many times get_seed_ips is called
    local count=$(grep -c 'seed_node_ips=.*get_seed_ips' "$SCRIPT_DIR/probe_nodes.sh" || true)

    if [ "$count" -eq 1 ]; then
        echo -e "${GREEN}[PASS]${NC} Seed nodes fetched only once (found $count occurrence)"
    else
        echo -e "${RED}[FAIL]${NC} Seed nodes fetched multiple times (found $count occurrences)"
        ((ERRORS++))
    fi
}

# Test 4: Verify seed failure exits script
test_seed_failure_exits() {
    echo -e "\n${YELLOW}[TEST 4]${NC} Checking seed failure handling..."

    # Check if there's an exit after seed_failure notification
    if grep -A 3 'send_notification "seed_failure"' "$SCRIPT_DIR/probe_nodes.sh" | grep -q 'exit 1'; then
        echo -e "${GREEN}[PASS]${NC} Script exits after seed failure"
    else
        echo -e "${RED}[FAIL]${NC} Script does not exit after seed failure"
        ((ERRORS++))
    fi
}

# Test 5: Verify associative array fix is present
test_associative_array_fix() {
    echo -e "\n${YELLOW}[TEST 5]${NC} Checking associative array fix..."

    if grep -q 'declare -A context=.*!2' "$SCRIPT_DIR/probe_nodes.sh"; then
        echo -e "${GREEN}[PASS]${NC} Associative array fix is present"
    else
        echo -e "${RED}[FAIL]${NC} Associative array fix not found"
        ((ERRORS++))
    fi
}

# Test 6: Syntax check
test_syntax() {
    echo -e "\n${YELLOW}[TEST 6]${NC} Checking bash syntax..."

    if bash -n "$SCRIPT_DIR/probe_nodes.sh" 2>/dev/null; then
        echo -e "${GREEN}[PASS]${NC} No syntax errors detected"
    else
        echo -e "${RED}[FAIL]${NC} Syntax errors found:"
        bash -n "$SCRIPT_DIR/probe_nodes.sh"
        ((ERRORS++))
    fi
}

# Cleanup
cleanup() {
    echo -e "\n${YELLOW}[CLEANUP]${NC} Removing test environment..."
    rm -rf "$TEST_DIR"
    echo -e "${GREEN}[DONE]${NC} Cleanup complete"
}

# Run all tests
main() {
    setup_test_env
    test_timestamp_defined
    test_threshold_notification
    test_no_duplicate_fetch
    test_seed_failure_exits
    test_associative_array_fix
    test_syntax
    cleanup

    echo ""
    echo "========================================="
    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN}ALL TESTS PASSED${NC}"
        echo "========================================="
        exit 0
    else
        echo -e "${RED}TESTS FAILED: $ERRORS error(s)${NC}"
        echo "========================================="
        exit 1
    fi
}

main
