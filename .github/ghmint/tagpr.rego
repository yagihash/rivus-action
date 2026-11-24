package ghmint

issuer := "https://token.actions.githubusercontent.com"

permissions := {"contents": "write", "pull_requests": "write", "issues": "read"}

allowed_events := {"push", "workflow_dispatch"}

# GitHub Actions appends immutable owner/repo IDs to the OIDC subject claim for repositories created after
# 2026-07-15 (repo:owner@<id>/repo@<id>:ref:...). Pin the actual IDs (yagihash = 1553908, rivus-action = 1470391000)
# rather than accepting any number, otherwise a recycled name could satisfy the rule.
# https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/
allow if {
	input.sub == "repo:yagihash@1553908/rivus-action@1470391000:ref:refs/heads/main"
	input.event_name in allowed_events
	input.job_workflow_ref == "yagihash/rivus-action/.github/workflows/tagpr.yml@refs/heads/main"
}
