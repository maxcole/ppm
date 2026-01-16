---
description: Create a Docker-based service package (n8n, postgres, redis, etc.)
---

# Docker Service Package Creation

You are creating a PPM package for a Docker-based service. First, read the PPM specification:

```
cat ~/.claude/docs/ppm.md
```

## Service Details

Create a Docker service package named: $ARGUMENTS

## Docker Service Package Pattern

Docker services use a specific structure that differs from typical packages:

```
packages/<n>/
├── install.sh                     # Lifecycle hooks
└── home/
    └── .local/
        └── share/
            └── <n>/
                ├── docker-compose.yml
                ├── .env.example
                └── data/          # Volume mount point (gitignored)
```

## Process

1. **Research Phase**:
   - Find official Docker image on Docker Hub
   - Review recommended docker-compose configurations
   - Identify required environment variables
   - Note volume mount requirements
   - Check for health check endpoints

2. **Create docker-compose.yml**:
   - Use official images with version tags (not `:latest` in production)
   - Configure restart policy (`unless-stopped`)
   - Set up health checks
   - Use named volumes or bind mounts to `./data/`
   - Expose minimal required ports
   - Use environment file (`.env`)

3. **Create .env.example**:
   - Document all environment variables
   - Use secure placeholder values
   - Note which vars are required vs optional

4. **Create install.sh**:
   ```bash
   dependencies() {
     echo ""  # Usually none, Docker handles it
   }
   
   install_linux() {
     # Ensure Docker is installed
     if ! command -v docker &>/dev/null; then
       echo "Docker required. Install via: https://docs.docker.com/engine/install/"
       exit 1
     fi
   }
   
   install_macos() {
     if ! command -v docker &>/dev/null; then
       echo "Docker Desktop required: https://www.docker.com/products/docker-desktop/"
       exit 1
     fi
   }
   
   post_install() {
     local service_dir="$XDG_DATA_HOME/<n>"
     
     # Create data directory
     mkdir -p "$service_dir/data"
     
     # Copy env template if .env doesn't exist
     if [[ ! -f "$service_dir/.env" ]]; then
       cp "$service_dir/.env.example" "$service_dir/.env"
       echo "Created .env from template - review and update values"
     fi
     
     echo ""
     echo "To start <n>:"
     echo "  cd $service_dir && docker-compose up -d"
     echo ""
     echo "Access at: http://localhost:<PORT>"
   }
   
   pre_remove() {
     local service_dir="$XDG_DATA_HOME/<n>"
     if [[ -f "$service_dir/docker-compose.yml" ]]; then
       echo "Stopping <n> containers..."
       docker-compose -f "$service_dir/docker-compose.yml" down 2>/dev/null || true
     fi
   }
   ```

5. **Create shell helper** in `home/.config/zsh/<n>.zsh`:
   ```bash
   # <n> service management
   alias <n>-up="docker-compose -f $XDG_DATA_HOME/<n>/docker-compose.yml up -d"
   alias <n>-down="docker-compose -f $XDG_DATA_HOME/<n>/docker-compose.yml down"
   alias <n>-logs="docker-compose -f $XDG_DATA_HOME/<n>/docker-compose.yml logs -f"
   alias <n>-restart="<n>-down && <n>-up"
   ```

6. **Add .gitignore** for data directory:
   ```
   data/
   .env
   ```

## Example: n8n Package

For context, here's what an n8n package might look like:

**docker-compose.yml**:
```yaml
services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "${N8N_PORT:-5678}:5678"
    environment:
      - GENERIC_TIMEZONE=${TZ:-UTC}
      - TZ=${TZ:-UTC}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER:-admin}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - WEBHOOK_URL=${N8N_WEBHOOK_URL:-http://localhost:5678}
    volumes:
      - ./data:/home/node/.n8n
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## Output

Present the complete package structure and all file contents for review before creating.
