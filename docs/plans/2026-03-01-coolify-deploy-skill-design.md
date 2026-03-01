# Coolify Deploy Skill Design

## Overview

A Claude skill for deploying applications to Coolify at `*.150people.app`. Supports static sites, Dockerfile builds, and Docker images with automatic deployment monitoring and failure debugging.

## Architecture

```
~/.claude/skills/coolify-deploy/
  SKILL.md              # Complete skill documentation with curl patterns

/Users/samschooler/repo/
  .env.coolify          # Credentials (project-specific)
```

## Configuration

**.env.coolify:**
```bash
COOLIFY_API_URL="https://island.150people.app/api/v1"
COOLIFY_API_TOKEN="<token>"
COOLIFY_DOMAIN="150people.app"
```

## Workflow

1. **Source credentials** - `source .env.coolify`
2. **Auto-discover infrastructure** - Query `/projects` and `/servers` endpoints
3. **Determine deployment type** - Static (nixpacks/static), Dockerfile, or Docker image
4. **Create application** - POST to appropriate `/applications/{type}` endpoint
5. **Set environment variables** - PATCH `/applications/{uuid}/envs/bulk` if needed
6. **Trigger deployment** - GET `/deploy/{uuid}`
7. **Monitor deployment** - Poll `/deployments/{uuid}` until complete
8. **On success** - Verify URL responds
9. **On failure** - Fetch logs, diagnose, fix, redeploy (loop until success)

## API Patterns

### Discovery
- `GET /projects` - List projects
- `GET /servers` - List servers

### Application Creation
- `POST /applications/public` - Public git repos
- `POST /applications/dockerfile` - Dockerfile builds
- `POST /applications/dockerimage` - Pre-built images

### Environment Variables
- `PATCH /applications/{uuid}/envs/bulk` - Bulk update

### Deployment
- `GET /deploy?uuid={uuid}` - Trigger deployment
- `GET /deployments/{uuid}` - Check status
- `GET /applications/{uuid}/logs` - Fetch logs

## Subdomain Strategy

- Default: Auto-generate from app/repo name (e.g., `my-app.150people.app`)
- Override: Explicit subdomain when specified

## Secrets Handling

- Check for `.env` file in repo first
- Allow inline override when invoking skill

## Proof of Concept

Deploy a basic static HTML site to `test.150people.app` to validate the skill works end-to-end.

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Wrapper script | No | Skill contains curl patterns directly, simpler |
| Discovery | Auto | Query API each time, more flexible |
| Subdomains | Both | Auto-generate default, allow explicit override |
| Credentials location | Repo-local | User requested env vars stay in this folder |
