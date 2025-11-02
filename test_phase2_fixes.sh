#!/bin/bash
# Test script for Phase 2 reliability improvements
# Tests: atomic state updates, numeric validation

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
echo "Phase 2 Fixes Test Suite"
echo "========================================="

# Setup test environment
setup_test_env() {
    echo -e "\n${YELLOW}[SETUP]${NC} Creating test environment..."
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    echo -e "${GREEN}[PASS]${NC} Test environment created"
}

# Test 1: Verify flock is used in state_update
test_flock_in_state_update() {
    echo -e "\n${YELLOW}[TEST 1]${NC} Checking flock in state_update()..."

    if grep -A 8 "^state_update()" "$SCRIPT_DIR/probe_nodes.sh" | grep -q "flock -x"; then
        echo -e "${GREEN}[PASS]${NC} flock is used for atomic state updates"
    else
        echo -e "${RED}[FAIL]${NC} flock not found in state_update()"
        ((ERRORS++))
    fi
}

# Test 2: Verify lock file is created
test_lock_file_defined() {
    echo -e "\n${YELLOW}[TEST 2]${NC} Checking lock file definition..."

    if grep -A 3 "^state_update()" "$SCRIPT_DIR/probe_nodes.sh" | grep -q "lock_file="; then
        echo -e "${GREEN}[PASS]${NC} Lock file is defined"
    else
        echo -e "${RED}[FAIL]${NC} Lock file not defined"
        ((ERRORS++))
    fi
}

# Test 3: Verify is_valid_number function exists
test_validation_function_exists() {
    echo -e "\n${YELLOW}[TEST 3]${NC} Checking is_valid_number() function..."

    if grep -q "^is_valid_number()" "$SCRIPT_DIR/probe_nodes.sh"; then
        echo -e "${GREEN}[PASS]${NC} is_valid_number() function exists"
    else
        echo -e "${RED}[FAIL]${NC} is_valid_number() function not found"
        ((ERRORS++))
    fi
}

# Test 4: Verify validation is used in determine_mbh
test_validation_in_mbh() {
    echo -e "\n${YELLOW}[TEST 4]${NC} Checking validation in determine_mbh()..."

    if grep -A 20 "^determine_mbh()" "$SCRIPT_DIR/probe_nodes.sh" | grep -q "is_valid_number"; then
        echo -e "${GREEN}[PASS]${NC} Validation is used in determine_mbh()"
    else
        echo -e "${RED}[FAIL]${NC} Validation not found in determine_mbh()"
        ((ERRORS++))
    fi
}

# Test 5: Verify MBH result is validated
test_mbh_result_validated() {
    echo -e "\n${YELLOW}[TEST 5]${NC} Checking MBH result validation..."

    if grep -A 3 'mbh=$(determine_mbh' "$SCRIPT_DIR/probe_nodes.sh" | grep -q "is_valid_number.*mbh"; then
        echo -e "${GREEN}[PASS]${NC} MBH result is validated after calculation"
    else
        echo -e "${RED}[FAIL]${NC} MBH result validation not found"
        ((ERRORS++))
    fi
}

# Test 6: Verify Phase 1 fixes are still present
test_phase1_still_present() {
    echo -e "\n${YELLOW}[TEST 6]${NC} Checking Phase 1 fixes are still present..."

    local phase1_errors=0

    if ! grep -q '^    local timestamp=' "$SCRIPT_DIR/probe_nodes.sh"; then
        echo -e "${RED}  [REGRESSION]${NC} Timestamp variable missing"
        ((phase1_errors++))
    fi

    if ! grep -q '"offline"|"threshold"' "$SCRIPT_DIR/probe_nodes.sh"; then
        echo -e "${RED}  [REGRESSION]${NC} Threshold notification type missing"
        ((phase1_errors++))
    fi

    if ! grep -q 'declare -A context=.*!2' "$SCRIPT_DIR/probe_nodes.sh"; then
        echo -e "${RED}  [REGRESSION]${NC} Associative array fix missing"
        ((phase1_errors++))
    fi

    if [ "$phase1_errors" -eq 0 ]; then
        echo -e "${GREEN}[PASS]${NC} All Phase 1 fixes still present"
    else
        echo -e "${RED}[FAIL]${NC} $phase1_errors Phase 1 regression(s) detected"
        ((ERRORS++))
    fi
}

# Test 7: Syntax check
test_syntax() {
    echo -e "\n${YELLOW}[TEST 7]${NC} Checking bash syntax..."

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
    test_flock_in_state_update
    test_lock_file_defined
    test_validation_function_exists
    test_validation_in_mbh
    test_mbh_result_validated
    test_phase1_still_present
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
