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

1. **Production** (republicreach.org)
   - Full dataset, daily updates
   - nginx caching: 1 hour
   - SSL with auto-renewal

2. **Beta** (beta.republicreach.org)
   - Feature testing environment
   - Same data as production
   - Shorter cache TTL

3. **Staging** (staging.republicreach.org)
   - Pre-production validation
   - Separate database
   - CI/CD integration

### Service Management

```bash
# systemd services
systemctl status republicreach-etl    # ETL orchestrator
systemctl status republicreach-web    # SvelteKit application
systemctl status martin               # Tile server

# Cron jobs
0 2 * * * /home/deploy/etl/run_daily_update.sh
```

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

### Debugging Data Issues

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

- API keys stored in environment variables
- Database credentials in systemd environment files
- No PII beyond public congressional data
- Rate limiting on all endpoints
- SQL injection prevention via SQLAlchemy

## Monitoring and Alerts

- Pipeline failures logged to `/home/deploy/etl/logs/`
- nginx access logs for traffic analysis
- Database slow query logging enabled
- Disk space monitoring for bulk data downloads

## Future Architecture Considerations

The modular pipeline design supports:
- Additional data sources (FEC, state legislatures)
- Real-time data streaming capabilities
- GraphQL API layer
- Webhook notifications for data updates
- Machine learning pipeline integration

---

*This documentation is maintained alongside the codebase. Update when making architectural changes.*