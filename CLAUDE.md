# RepublicReach Technical Documentation

This document provides comprehensive technical details about the RepublicReach platform for future development and documentation efforts.

## Project Structure

```
/home/deploy/
├── etl/                          # ETL Pipeline System
│   ├── orchestrator.py           # Pipeline execution manager
│   ├── models.py                 # SQLAlchemy ORM models
│   ├── database.py               # Database operations layer
│   ├── congress_sdk.py           # Congress.gov API wrapper
│   ├── config_pydantic.py        # Configuration schema
│   ├── pipelines/                # Individual pipeline implementations
│   │   ├── members.py            # Congressional members data
│   │   ├── congress_data.py      # Bills and sponsorships
│   │   ├── district_offices.py   # Office locations
│   │   └── state_info.py         # State government data
│   └── data/                     # Static data files
├── LIBERTY-SITE/                 # Production web application
│   ├── src/
│   │   ├── routes/               # SvelteKit pages
│   │   │   ├── +page.svelte      # Home page
│   │   │   ├── map/              # Interactive district map
│   │   │   ├── representatives/  # Member directory
│   │   │   └── bills/            # Legislative tracking
│   │   └── lib/                  # Shared components and stores
│   └── deploy/                   # Deployment configuration
└── LIBERTY-SITE-STAGING/         # Staging environment

/etc/nginx/sites-enabled/         # nginx configurations
├── republicreach.org.conf        # Production site
├── beta.republicreach.org.conf   # Beta site
├── staging.republicreach.org.conf # Staging site
└── tiles.republicreach.org.conf  # Map tile server
```

## Data Model

### Core Entities

```python
# Member - Congressional representatives
- bioguide_id (Primary Key)
- api_data (JSONB): Complete Congress.gov API response
- first_name, last_name, official_full_name
- state, district, party
- terms (JSONB): Array of service terms
- depiction_image_url, depiction_attribution
- party_history (JSONB): Party affiliation changes
- sponsored_legislation (JSONB): Recent bills sponsored
- cosponsored_legislation (JSONB): Recent bills cosponsored
- leadership_roles, committees
- update_date: Last API update timestamp

# Bill - Congressional legislation
- bill_id (Primary Key): Format "{congress}{type}{number}"
- api_data (JSONB): Complete bill data
- congress, type, number
- introduced_date, latest_action_date
- title, policy_area
- update_date: Last update timestamp

# CongressionalDistrict - Geographic boundaries
- id (Primary Key)
- state_code, district_code
- congress_number
- boundary (PostGIS Geometry): District polygon
- representative_bioguide_id (Foreign Key)
- last_updated

# DistrictOffice - Physical office locations
- id (Primary Key)
- member_bioguide_id (Foreign Key)
- office_type: "district" or "capitol"
- address, city, state, zip
- phone, fax
- hours, additional_info
- latitude, longitude
```

### Relationships

- **Member ↔ Bill**: Many-to-many through Sponsorship table
- **Member ↔ CongressionalDistrict**: One-to-many (Senators have multiple)
- **Member ↔ DistrictOffice**: One-to-many

### ETL Tracking Tables

```python
# EtlRun - Pipeline execution tracking
- run_id, pipeline_name, status
- started_at, completed_at, duration
- records_processed, records_failed
- error_message, error_details

# EtlLog - Detailed execution logs
- log_id, run_id, log_level
- message, details (JSONB)
- created_at
```

## ETL Pipeline Details

### Pipeline Architecture

1. **BasePipeline Abstract Class**
   ```python
   class BasePipeline(ABC):
       async def execute() -> PipelineResult
       async def extract() -> Any
       async def transform(data: Any) -> Any
       async def load(data: Any) -> LoadResult
       async def validate() -> ValidationResult
       async def cleanup() -> None
   ```

2. **Orchestration Flow**
   - Dependency resolution using topological sort
   - Parallel execution of independent pipelines
   - Configurable worker pool (default: 3)
   - Comprehensive error tracking and recovery

3. **Pipeline Implementations**

   **MembersPipeline**
   - Sources: Congress.gov Members API
   - Update strategy: Incremental (checks updateDate)
   - Special handling: Party history, leadership roles
   - Rate limiting: 1000 requests/hour

   **CongressDataPipeline**
   - Sources: Congressional bulk XML files
   - Processing: Async XML parsing with streaming
   - Data types: Bills (HR, S, HJRES, etc.), Sponsorships
   - Batch size: 1000 records

   **DistrictOfficesPipeline**
   - Sources: YAML configuration files
   - Validation: Address geocoding verification
   - Updates: Manual trigger only

   **StateInfoPipeline**
   - Sources: Wikidata SPARQL endpoint
   - Query: State government structure
   - Caching: 7-day TTL

### Configuration System

The project uses a layered configuration approach:

1. **Base Configuration** (`config.yaml`)
2. **Environment Variables** (override YAML)
3. **Pydantic Validation** (type safety)

Key configuration sections:
- Database connection and pooling
- API credentials and rate limits
- Pipeline-specific settings
- Logging and monitoring
- Memory and performance limits

## Frontend Architecture

### State Management (Svelte 5 Runes)

```typescript
// location.store.svelte.ts
class LocationStore {
  private location = $state<Location>()
  private isLoading = $state<boolean>(false)
  
  get current() { return this.location }
  
  async updateFromMap(lat: number, lng: number) {
    // Updates trigger reactive UI changes
  }
}

// Cross-store reactivity
$effect(() => {
  if (locationStore.district) {
    membersStore.fetchForDistrict(locationStore.district)
  }
})
```

### Key Components

1. **DistrictMap.svelte**
   - MapLibre GL integration
   - Vector tiles from tiles.republicreach.org
   - Click-to-select districts
   - Reactive highlighting

2. **RepresentativeCard.svelte**
   - Displays member information
   - Links to office contacts
   - Shows recent legislative activity

3. **State Management Flow**
   ```
   User Action → Store Update → $effect Triggers → API Call → UI Update
   ```

## API Endpoints

### Public API Routes

```typescript
// GET /api/members
// Query params: state, district, chamber
Returns: Member[]

// GET /api/bills
// Query params: congress, type, sponsor, offset, limit
Returns: { bills: Bill[], total: number }

// GET /api/districts/lookup
// Query params: lat, lng
Returns: { state: string, district: number }

// GET /api/states/:stateCode
Returns: StateInfo with legislature details
```

### Tile Server

```
https://tiles.republicreach.org/{z}/{x}/{y}.pbf
- Martin vector tile server
- PostGIS ST_AsMVT queries
- nginx caching layer
```

## Deployment Architecture

### Environment Setup

1. **Production** (beta.republicreach.org)
   - Branch: `production`
   - Database: `gov`
   - Port: 3000
   - Full dataset with daily ETL updates
   - nginx caching: 1 hour
   - SSL with Let's Encrypt auto-renewal

2. **Staging** (staging.republicreach.org)
   - Branch: `main`
   - Database: `gov_staging`
   - Port: 4173
   - Pre-production validation
   - Database synced from production
   - CI/CD automatic deployment

3. **Development** (localhost)
   - Branch: feature branches
   - Database: `gov_local`
   - Port: 5173
   - Local PostgreSQL instance

### CI/CD Pipeline (GitHub Actions)

The `.github/workflows/deploy.yml` orchestrates the deployment:

#### Build & Test Job
```yaml
- Checkout code
- Setup Node.js 22 with npm cache
- Install dependencies (npm ci)
- Run linting (npm run lint)
- Run type checking (npm run check)
- Build application (npm run build)
```

#### Staging Deployment (Auto on main push)
```yaml
- SSH to server as deploy user
- Pull latest main branch
- Install dependencies
- Backup current build
- Build with staging environment
- Restart liberty-staging service
- Health check on localhost:4173
```

#### Production Deployment (Manual approval required)
```yaml
- Same as staging but:
- Requires environment approval
- Deploys to LIBERTY-SITE directory
- Restarts liberty-beta service
- Health check on localhost:3000
- Maintains last 5 build backups
```

### Service Management

#### systemd Service Configuration

The services are defined in `deploy/systemd/`:

**liberty-beta.service** (Production):
- Port: 3000
- Environment: production
- Working directory: /home/deploy/LIBERTY-SITE
- Origin: https://beta.republicreach.org
- Environment file: /home/deploy/.env.production

**liberty-staging.service** (Staging):
- Port: 4173
- Environment: staging
- Working directory: /home/deploy/LIBERTY-SITE-STAGING
- Origin: https://staging.republicreach.org
- Environment file: /home/deploy/.env.staging

Both services include:
- Automatic restart on failure
- Security hardening (NoNewPrivileges, PrivateTmp)
- Journal logging with service identifiers
- NVM integration for Node.js version management

#### Service Commands

```bash
# Service management (user-level)
systemctl --user status liberty-beta      # Production status
systemctl --user status liberty-staging   # Staging status
systemctl --user restart liberty-beta     # Restart production
systemctl --user restart liberty-staging  # Restart staging

# View logs
journalctl --user -u liberty-beta -f     # Production logs
journalctl --user -u liberty-staging -f  # Staging logs

# ETL orchestration
cd /home/deploy/etl && python -m orchestrator
```

### nginx Configuration

Sites enabled:
- `republicreach.org.conf` - Production redirect
- `beta.republicreach.org.conf` - Production app
- `staging.republicreach.org.conf` - Staging app
- `tiles.republicreach.org.conf` - Martin tile server

Key nginx features:
- Reverse proxy to Node.js services
- Gzip compression
- Cache headers for static assets
- SSL termination
- Health check endpoints

## Development Workflow

### Running ETL Pipelines

```bash
cd /home/deploy/etl

# Run all pipelines
python -m orchestrator

# Run specific pipeline
python -m pipelines.members

# Configuration override
CONGRESS_API_KEY=xxx python -m orchestrator
```

### Frontend Development

```bash
cd /home/deploy/LIBERTY-SITE

# Development server
npm run dev

# Type checking
npm run check

# Build for production
npm run build
```

## Common Tasks

### Deployment Tasks

#### Deployment Readiness Check
```bash
# Run comprehensive environment validation
cd /home/deploy/RepublicReach/deploy/scripts
./check-env.sh
```

This script validates:
- Directory structure (production, staging, backups)
- Environment files and DATABASE_URL configuration
- Database connectivity for both environments
- systemd service installation and status
- SSH key configuration
- GitHub secrets (if gh CLI is available)
- Node.js installation

#### Database Synchronization
```bash
# Safe sync from production to staging
cd /home/deploy/RepublicReach/deploy/scripts
./db-sync-safe.sh production staging
```

Features:
- Automatic backup of target database before sync
- Uses `pg_dump --clean` for safe object replacement
- Excludes ETL tracking tables when syncing to staging
- Removes superuser-only commands (EXTENSION operations)
- Maintains last 5 backups automatically
- No manual DROP DATABASE required

#### Manual Deployment
```bash
cd /home/deploy/LIBERTY-SITE-STAGING
git pull origin main
npm ci
npm run build
systemctl --user restart liberty-staging
```

#### Rollback Procedure
```bash
cd /home/deploy/LIBERTY-SITE
# Find backup
ls -la build.backup.*
# Restore previous build
mv build build.failed
mv build.backup.20250615_120000 build
systemctl --user restart liberty-beta
```

### Adding a New Data Source

1. Create pipeline in `etl/pipelines/`
2. Implement BasePipeline interface
3. Add to orchestrator configuration
4. Update models.py if needed
5. Run migrations

### Updating District Boundaries

1. Download new shapefiles
2. Run `load_map_data/import_boundaries.sh`
3. Update Martin configuration
4. Clear tile cache

### Debugging Issues

#### Check Service Status
```bash
# Application logs
journalctl --user -u liberty-beta -n 100
journalctl --user -u liberty-staging -n 100

# nginx logs
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

#### Database Queries
```sql
-- Check pipeline status
SELECT * FROM etl_runs 
WHERE pipeline_name = 'members' 
ORDER BY started_at DESC LIMIT 10;

-- Verify data freshness
SELECT MAX(update_date) FROM members;

-- District lookup issues
SELECT * FROM congressional_districts
WHERE ST_Contains(boundary, ST_SetSRID(ST_MakePoint(lng, lat), 4326));
```

#### Health Checks
```bash
# Production
curl https://beta.republicreach.org/api/state-info
curl https://beta.republicreach.org/api/representatives?state=CA&district=1

# Staging
curl https://staging.republicreach.org/api/state-info

# Tile server
curl https://tiles.republicreach.org/14/2621/6333.pbf -I
```

## Performance Optimization

### Database Indexes

```sql
-- Frequent lookups
CREATE INDEX idx_members_state_district ON members(state, district);
CREATE INDEX idx_bills_sponsor ON sponsorships(bioguide_id);

-- Spatial queries
CREATE INDEX idx_districts_boundary ON congressional_districts USING GIST(boundary);

-- JSONB queries
CREATE INDEX idx_members_api_data ON members USING GIN(api_data);
```

### Caching Strategy

1. **nginx**: Static assets, API responses
2. **Application**: Computed state legislature data
3. **Database**: Materialized views for complex queries
4. **CDN**: Map tiles and images

## Security Considerations

### Access Control
- SSH key-based authentication only (password auth disabled)
- Deployment user (`deploy`) with limited sudo access
- Database user with minimal required permissions
- Firewall rules (ufw) restricting ports

### Secrets Management
```bash
# Production secrets
/home/deploy/.env.production    # Mode: 600
/home/deploy/.env.staging       # Mode: 600

# GitHub Actions secrets
SERVER_HOST                     # Server IP
SERVER_USER                     # deploy
SERVER_PORT                     # SSH port
SERVER_SSH_KEY                  # ED25519 private key
```

### Application Security
- Environment variables for sensitive data
- No hardcoded credentials in code
- SQL injection prevention via SQLAlchemy ORM
- XSS protection with SvelteKit's built-in escaping
- CORS configuration for API endpoints
- Rate limiting on nginx level

## Backup & Recovery

### Database Backups
```bash
# Daily automated backup (cron)
0 3 * * * pg_dump gov | gzip > /home/deploy/db-backups/gov_$(date +\%Y\%m\%d).sql.gz

# Manual backup
pg_dump gov > /home/deploy/backups/gov_manual_$(date +%Y%m%d_%H%M%S).sql

# Restore from backup
gunzip < /home/deploy/db-backups/gov_20250615.sql.gz | psql gov_restore
```

### Application Backups
- Build artifacts: Last 5 versions retained automatically
- Configuration: Version controlled in git
- nginx configs: Backed up in `/home/deploy/backups/nginx/`

### Disaster Recovery Plan
1. **Database failure**: Restore from daily backup (max 24h data loss)
2. **Application failure**: Rollback to previous build
3. **Server failure**: Provision new VPS, restore from backups
4. **Data corruption**: ETL pipelines can rebuild from source

## Monitoring and Alerts

### Application Monitoring
- Health endpoints checked post-deployment
- systemd service status monitoring
- nginx access/error logs
- Database connection pool metrics

### Log Locations
```bash
# Application logs
/home/deploy/.pm2/logs/          # If using PM2
journalctl --user -u liberty-*   # systemd logs

# ETL logs
/home/deploy/etl/logs/
/home/deploy/etl/etl_runs.log

# System logs
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/postgresql/
```

### Performance Monitoring
```bash
# Server resources
htop                            # CPU/Memory usage
df -h                          # Disk usage
netstat -tlpn                  # Network connections

# Database performance
psql gov -c "SELECT * FROM pg_stat_activity"
psql gov -c "SELECT * FROM pg_stat_user_tables"
```

## Future Architecture Considerations

The modular pipeline design supports:
- Additional data sources (FEC, state legislatures)
- Real-time data streaming capabilities
- GraphQL API layer
- Webhook notifications for data updates
- Machine learning pipeline integration

---

*This documentation is maintained alongside the codebase. Update when making architectural changes.*