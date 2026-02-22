# Contributing

## Commit Message Format

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automated semantic releases.

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | Description | Version bump |
|------|-------------|--------------|
| `feat` | A new feature | minor |
| `fix` | A bug fix | patch |
| `docs` | Documentation changes | patch |
| `style` | Code style changes (formatting, etc.) | patch |
| `refactor` | Code refactoring | patch |
| `test` | Adding or updating tests | patch |
| `build` | Build system changes | patch |
| `ci` | CI/CD changes | patch |
| `perf` | Performance improvements | patch |
| `revert` | Reverting changes | patch |
| `chore` | Maintenance tasks | no release |

## Breaking Changes

Add `BREAKING CHANGE:` in the footer or use `!` after the type to trigger a major version bump:

```
feat!: redesign API
```

or

```
feat: add new endpoint

BREAKING CHANGE: removes the legacy /v1 API
```

## Examples

- `feat: add Litecoin price display` → 0.1.0 → 0.2.0
- `fix: resolve DB connection pool exhaustion` → 0.2.0 → 0.2.1
- `feat!: replace REST API with GraphQL` → 0.2.1 → 1.0.0
- `docs: update setup instructions` → 0.2.1 → 0.2.2
- `chore: update dependencies` → no version change

## Automated Release Process

When you push to `main`:

1. Semantic-release analyzes commit messages since the last release
2. Determines the version bump based on commit types
3. Updates `package.json` version field
4. Generates a changelog
5. Creates a GitHub release with release notes
6. Commits the version update back to the repo with `[skip ci]`
