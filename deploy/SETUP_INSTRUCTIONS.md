# Manual Setup Instructions

## One-Time Server Setup

### 1. Create Required Directories
```bash
mkdir -p /home/deploy/LIBERTY-SITE-STAGING
mkdir -p /home/deploy/db-backups
mkdir -p ~/.config/systemd/user/
```

### 2. Create Environment Files
Create `/home/deploy/.env.production`:
```bash
DATABASE_URL=postgresql://your_user:your_password@localhost:5432/your_db
NODE_ENV=production
```

Create `/home/deploy/.env.staging`:
```bash
DATABASE_URL=postgresql://your_user:your_password@localhost:5432/your_staging_db
NODE_ENV=staging
```

Set permissions:
```bash
chmod 600 /home/deploy/.env.*
```

### 3. Install Systemd User Services
```bash
cp /home/deploy/LIBERTY-SITE/deploy/systemd/*.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable liberty-beta liberty-staging
```

### 4. Create Staging Database
```bash
createdb -U your_user your_staging_db
psql -U your_user your_staging_db -c "CREATE EXTENSION IF NOT EXISTS postgis;"
```

### 5. Initial Database Sync
```bash
cd /home/deploy/LIBERTY-SITE/deploy/scripts
./db-sync.sh production staging
```