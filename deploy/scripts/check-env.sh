#!/bin/bash
# Environment and deployment readiness check script

set -e

echo "🔍 RepublicReach Deployment Readiness Check"
echo "=========================================="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check function
check() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        FAILED=1
    fi
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

FAILED=0

echo -e "\n📁 Directory Structure:"
[ -d "/home/deploy/LIBERTY-SITE" ] && check 0 "Production directory exists" || check 1 "Production directory missing"
[ -d "/home/deploy/LIBERTY-SITE-STAGING" ] && check 0 "Staging directory exists" || check 1 "Staging directory missing"
[ -d "/home/deploy/db-backups" ] && check 0 "Backup directory exists" || check 1 "Backup directory missing"
[ -d "$HOME/.config/systemd/user" ] && check 0 "Systemd user directory exists" || check 1 "Systemd user directory missing"

echo -e "\n🔐 Environment Files:"
if [ -f "/home/deploy/.env.production" ]; then
    check 0 "Production env file exists"
    # Check if DATABASE_URL is set (without showing the value)
    if grep -q "DATABASE_URL=" /home/deploy/.env.production; then
        check 0 "Production DATABASE_URL is set"
    else
        check 1 "Production DATABASE_URL is missing"
    fi
else
    check 1 "Production env file missing"
fi

if [ -f "/home/deploy/.env.staging" ]; then
    check 0 "Staging env file exists"
    if grep -q "DATABASE_URL=" /home/deploy/.env.staging; then
        check 0 "Staging DATABASE_URL is set"
    else
        check 1 "Staging DATABASE_URL is missing"
    fi
else
    check 1 "Staging env file missing"
fi

echo -e "\n🗄️ Database Check:"
# Check if databases exist using connection from env files
if [ -f "/home/deploy/.env.production" ]; then
    source /home/deploy/.env.production
    if psql "$DATABASE_URL" -c "SELECT 1" &>/dev/null; then
        check 0 "Production database connection works"
    else
        check 1 "Production database connection failed"
    fi
else
    warn "Cannot check production database - env file missing"
fi

if [ -f "/home/deploy/.env.staging" ]; then
    source /home/deploy/.env.staging
    if psql "$DATABASE_URL" -c "SELECT 1" &>/dev/null; then
        check 0 "Staging database connection works"
    else
        check 1 "Staging database connection failed"
    fi
else
    warn "Cannot check staging database - env file missing"
fi

echo -e "\n⚙️ Systemd Services:"
if [ -f "$HOME/.config/systemd/user/liberty-beta.service" ]; then
    check 0 "Production service file installed"
    if systemctl --user is-enabled liberty-beta &>/dev/null; then
        check 0 "Production service is enabled"
    else
        warn "Production service not enabled (run: systemctl --user enable liberty-beta)"
    fi
else
    check 1 "Production service file missing"
fi

if [ -f "$HOME/.config/systemd/user/liberty-staging.service" ]; then
    check 0 "Staging service file installed"
    if systemctl --user is-enabled liberty-staging &>/dev/null; then
        check 0 "Staging service is enabled"
    else
        warn "Staging service not enabled (run: systemctl --user enable liberty-staging)"
    fi
else
    check 1 "Staging service file missing"
fi

echo -e "\n🔑 SSH Key Check:"
if [ -f "$HOME/.ssh/id_ed25519" ] || [ -f "$HOME/.ssh/id_rsa" ]; then
    check 0 "SSH key exists for deploy user"
    if [ -f "$HOME/.ssh/authorized_keys" ]; then
        check 0 "Authorized keys file exists"
    else
        warn "No authorized_keys file - make sure your key is added"
    fi
else
    check 1 "No SSH key found for deploy user"
fi

echo -e "\n🐙 GitHub Secrets Check (requires 'gh' CLI):"
if command -v gh &> /dev/null; then
    # Only check if authenticated
    if gh auth status &>/dev/null; then
        echo "Checking GitHub secrets..."
        SECRETS=$(gh secret list 2>/dev/null || echo "")
        
        for secret in SERVER_HOST SERVER_USER SERVER_PORT SERVER_SSH_KEY STAGING_DATABASE_URL PRODUCTION_DATABASE_URL; do
            if echo "$SECRETS" | grep -q "^$secret"; then
                check 0 "GitHub secret '$secret' is set"
            else
                check 1 "GitHub secret '$secret' is missing"
            fi
        done
    else
        warn "GitHub CLI not authenticated (run: gh auth login)"
    fi
else
    warn "GitHub CLI not installed - cannot check secrets"
fi

echo -e "\n📦 Node.js Check:"
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    check 0 "Node.js installed: $NODE_VERSION"
else
    check 1 "Node.js not found"
fi

echo -e "\n=========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Ready for deployment.${NC}"
else
    echo -e "${RED}❌ Some checks failed. Please fix the issues above.${NC}"
    exit 1
fi
