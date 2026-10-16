# Cadena Engineering - Common Rules

Read common-rules.md in this directory before substantial code changes.

## Task-specific rules
- Performance: inspect relevant files in rules/performance/.
- Bug fixing: inspect relevant files in rules/bug-fixing/.
- Feature development: inspect relevant files in rules/feature-development/.

Follow the target project's existing architecture and conventions.
Preserve business behavior unless explicitly asked to change it.
Avoid unrelated refactoring.
Never expose secrets or credentials.
Never claim tests passed unless they were actually executed.
Distinguish verified facts from assumptions.
