---
schema: 2
profile: standard@2

processes:
  commit:
    issue: required
    safeguards:
      allowArtifactPaths: []
      maxFileBytes: 5242880
      maxReviewDiffBytes: 307200
    checks:
      - id: project
        command: ["./scripts/check"]
        timeoutSeconds: 900
    reviews: []

  pullRequest:
    issue: required
    checks:
      - id: project
        command: ["./scripts/check"]
        timeoutSeconds: 900
    statuses: []
    reviews:
      - id: regression
        model: openai-codex/gpt-5.4-mini
        actor: repflow-review
        prompt: >-
          Review the complete target/candidate diff for correctness, regressions,
          accidental behavior removal, maintainability, and missing tests or
          documentation. Pay particular attention to database migrations,
          backup and restore behavior, data integrity, historical log
          immutability, and interactions with existing features. Cite concrete
          evidence and do not request unrelated features.
        requiredRecommendation: approve
        timeoutSeconds: 900
    guidance:
      includePolicyBody: true
      files: []

  merge:
    strategy: rebase
    authorization: manual

notifications:
  forgejo: true
---

# Project expectations

Meal of Record is a local-first personal nutrition application whose data may represent years of user history. Favor straightforward, testable changes and preserve existing user data and behavior unless an issue explicitly requires a change.

Keep the bundled read-only reference database separate from the writable live database. Logged nutritional data is historical information: later edits to foods, portions, recipes, reference data, or targets must not silently change prior logs.

# Review expectations

Review every pull request for correctness, regression, accidental reversion, maintainability, and appropriate tests. Findings must cite concrete evidence from the candidate and should not expand the issue with unrelated improvements.

Give additional scrutiny to schema migrations, backup and restore behavior, persisted preferences, image storage and references, recipe relationships, goals and targets, and interactions across logging, search, recipes, and the log queue. Changes touching persisted state should include representative non-personal regression coverage and safe failure behavior where applicable.

# Operational invariants

- Never commit real personal databases, backups, credentials, signing keys, or user images.
- Existing live databases must migrate forward without silent data loss or reinterpretation.
- Historical logged-food snapshots must retain their original nutritional meaning.
- Backup and restore changes must preserve documented application state and must fail safely on malformed, incomplete, or incompatible input.
- Release and deployment operations are unsupported until complete project-owned adapters are added through a separately reviewed policy change.

# Evidence

`./scripts/check` is the repository-owned aggregate check. It resolves locked Flutter dependencies, runs analysis with errors fatal, and runs the complete Flutter test suite. Existing nonfatal analyzer findings are tracked separately and should not be hidden merely to satisfy the gate.
