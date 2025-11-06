# Renovate Setup

## Required Secret: RENOVATE_TOKEN

Renovate requires a GitHub Personal Access Token to create pull requests and trigger workflows.

### Creating the Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Name: `Renovate Token`
4. Expiration: Set to your preference (90 days, 1 year, or no expiration)
5. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
6. Click "Generate token"
7. Copy the token (you won't see it again!)

### Adding to Repository

1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `RENOVATE_TOKEN`
4. Value: Paste the token from above
5. Click "Add secret"

### Verification

After adding the secret, trigger Renovate manually:

```bash
gh workflow run renovate.yaml
```

Check the Actions tab for the workflow run. If successful, Renovate will:
- Create a "Dependency Dashboard" issue
- Scan for updates
- Create PRs for any outdated dependencies

## Troubleshooting

**Workflow fails with "Bad credentials"**
- Check that RENOVATE_TOKEN secret is set correctly
- Verify token has `repo` and `workflow` scopes
- Token may have expired - generate a new one

**No PRs created**
- Dependencies may already be up-to-date
- Check Dependency Dashboard issue for status
- Review Renovate logs in workflow run

**Auto-merge not working**
- Check CI passes on Renovate PRs
- Verify 3-day minimum release age has passed
- Confirm package rule allows auto-merge

## Configuration

See `renovate.json` for configuration details:
- **Schedule**: Daily at 2am UTC
- **Auto-merge**: Patch updates only, after 3 days
- **Grouping**: By dependency type (Actions, Docker, Helm)
- **Dashboard**: Enabled (creates issue with update status)

## Manual Operations

**Trigger Renovate immediately:**
```bash
gh workflow run renovate.yaml
```

**Disable auto-merge for specific update:**
Add to `renovate.json`:
```json
{
  "packageRules": [
    {
      "matchPackageNames": ["package-name"],
      "automerge": false
    }
  ]
}
```

**Change schedule:**
Edit `schedule` in `renovate.json`:
```json
{
  "schedule": ["before 5am on Monday"]
}
```
