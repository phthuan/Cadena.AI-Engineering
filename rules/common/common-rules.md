# Cadena Engineering — Common Rules

## General principles

- Inspect the existing code before making changes.
- Follow the project's established architecture and coding conventions.
- Avoid unrelated refactoring.
- Explain the root cause before proposing a bug fix.
- For performance work, identify bottlenecks and measure when possible.
- For new features, consider validation, security, error handling and tests.
- Never claim tests passed unless they were actually executed.
- Never expose secrets, tokens or credentials.

## Task-specific rules

- Performance tasks: read relevant files in `rules/performance/`.
- Bug-fixing tasks: read relevant files in `rules/bug-fixing/`.
- Feature tasks: read relevant files in `rules/feature-development/`.

Before making substantial changes, inspect applicable shared rules and the target project's existing conventions.
