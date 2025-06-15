# RepublicReach CI/CD Pipeline Setup

## Overview

This CI/CD pipeline provides automated testing and deployment for RepublicReach, supporting local development, staging, and production environments.

## Architecture

```
Local Development → GitHub → CI/CD Pipeline → Staging → Production
                                    ↓
                              Automated Tests
```

## Environment Setup

### 1. Server Setup (One-time)

Follow the manual setup instructions in `/deploy/SETUP_INSTRUCTIONS.md` on your production server.

### 2. Configure Environment Variables

Edit the following files on your server:
- `/home/deploy/.env.production` - Production environment variables
- `/home/deploy/.env.staging` - Staging environment variables

Required variables:
```bash
DATABASE_URL=postgresql://user:pass@localhost:5432/dbname
NODE_ENV=production|staging
```

### 3. Database Setup

#### Create Staging Database
```bash
# Sync production data to staging
cd /home/deploy/LIBERTY-SITE/deploy/scripts
./db-sync.sh production staging
```

#### Local Development Database
On your local machine:
```bash
# Create local database
createdb gov_local
psql gov_local -c "CREATE EXTENSION IF NOT EXISTS postgis;"

# Get initial data from production (one-time)
ssh deploy@yourserver "pg_dump gov" | psql gov_local
```

### 4. GitHub Secrets Configuration

Add these secrets to your GitHub repository:
- `SERVER_HOST` - Your server IP/hostname
- `SERVER_USER` - SSH username (deploy)
- `SERVER_PORT` - SSH port (usually 22)
- `SERVER_SSH_KEY` - Private SSH key for deployment
- `STAGING_DATABASE_URL` - Staging database connection string
- `PRODUCTION_DATABASE_URL` - Production database connection string

### 5. Systemd Services

Enable and start the services:
```bash
# Production
sudo systemctl enable liberty-beta
sudo systemctl start liberty-beta

# Staging
sudo systemctl enable liberty-staging
sudo systemctl start liberty-staging

# Check status
sudo systemctl status liberty-beta
sudo systemctl status liberty-staging
```

## Deployment Workflow

### Automatic Deployments

1. **Push to `main` branch** → Deploys to staging automatically
2. **Push to `production` branch** → Deploys to production (with approval)

### Manual Database Sync

When needed, sync databases between environments:
```bash
cd /home/deploy/LIBERTY-SITE/deploy/scripts
./db-sync.sh production staging  # Copy prod to staging
```

## Local Development Workflow

### 1. Initial Setup
```bash
# Clone repository
git clone https://github.com/gtrev500/LIBERTY-SITE.git
cd LIBERTY-SITE

# Install dependencies
npm install

# Set up local environment
echo "DATABASE_URL=postgresql://localhost:5432/gov_local" > .env.local
```

### 2. Development Cycle
```bash
# Start development server
npm run dev

# Run tests before pushing
npm run lint
npm run check
npm test
```

### 3. Deployment Process
```bash
# Deploy to staging
git push origin main

# Deploy to production (after testing on staging)
git checkout production
git merge main
git push origin production
```

## ETL Pipeline Integration

### Manual ETL Updates
```bash
# On server
cd /home/deploy/etl
gov-etl run --all

# Sync to staging after ETL updates
cd /home/deploy/LIBERTY-SITE/deploy/scripts
./db-sync.sh production staging
```

### Scheduled ETL (Future)
Add to crontab:
```cron
# Run ETL daily at 2 AM
0 2 * * * cd /home/deploy/etl && gov-etl run --all >> /home/deploy/etl/logs/cron.log 2>&1

# Sync to staging after ETL
30 2 * * * cd /home/deploy/LIBERTY-SITE/deploy/scripts && ./db-sync.sh production staging >> /home/deploy/db-backups/sync.log 2>&1
```

## Monitoring

### Check Service Status
```bash
# View logs
sudo journalctl -u liberty-beta -f
sudo journalctl -u liberty-staging -f

# Check service status
sudo systemctl status liberty-beta
sudo systemctl status liberty-staging
```

### Health Checks
- Production: https://beta.republicreach.org/api/state-info
- Staging: https://staging.republicreach.org/api/state-info

## Rollback Procedure

If deployment fails:
```bash
# On server
cd /home/deploy/LIBERTY-SITE
mv build build.failed
mv build.backup.TIMESTAMP build
sudo systemctl restart liberty-beta
```

## Security Notes

1. **Database Credentials**: Stored in environment files with 600 permissions
2. **SSH Keys**: Use ED25519 or RSA keys with passphrase
3. **IP Restriction**: Staging environment restricted to specific IPs
4. **SSL**: All traffic uses HTTPS via nginx

## Troubleshooting

### Service Won't Start
```bash
# Check logs
sudo journalctl -u liberty-beta -n 100
# Verify environment file
sudo -u deploy cat /home/deploy/.env.production
```

### Database Connection Issues
```bash
# Test connection
psql $DATABASE_URL -c "SELECT 1"
# Check PostgreSQL status
sudo systemctl status postgresql
```

### Build Failures
```bash
# Check Node version
node --version  # Should be v22+
# Clear cache and rebuild
rm -rf node_modules package-lock.json
npm install
npm run build
```