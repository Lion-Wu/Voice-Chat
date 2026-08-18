# Development Rules

## Implementation

- Treat the requested scope as a hard boundary. Do not add unrelated cleanup, refactors, features, dependency changes, or compatibility work.
- Inspect the real code, interfaces, documentation, call sites, configuration, and runtime path before changing behavior. Do not guess APIs or business rules.
- Fix every defect at its root cause by locating the responsible ownership, lifecycle, state, protocol, persistence, concurrency, layout, or execution boundary.
- Never add a fallback, workaround, retry, delay, forced refresh, cache reset, source rewrite, error suppression, or UI mask to conceal a defect. Preserve intentional existing product behavior unless the task changes it.
- If the root cause is not established, keep investigating or report the blocker; do not ship a speculative patch.
- Do not overengineer for contrived or extremely unlikely cases unless they create a realistic security, privacy, data-loss, or core-reliability risk.
- Reuse existing components and seams before creating new abstractions, helpers, APIs, state, or services.
- Keep one source of truth and clear ownership. Separate UI, domain logic, persistence, transport, and system-framework integration.
- Make the smallest cohesive change that preserves unaffected behavior and improves long-term maintainability.
- Follow the surrounding code style. Do not mass-format or rewrite unrelated code.
- Production paths must handle realistic failure, cancellation, cleanup, persistence, security, and authorization correctly. Never rely on mocks, hard-coded success, or debug-only assumptions.
- Keep build, package, resource, and target wiring correct when files change.
- Preserve all pre-existing user work. Undo only task-owned hunks and never discard unrelated changes.
- Investigate ambiguity first; ask only when a material product, scope, authorization, or data-safety decision remains unresolved.

## Build and Tests

- Every code change must build successfully for all affected available targets with zero errors and zero warnings.
- Fix warnings at their cause; do not suppress them. Report unrelated pre-existing warnings precisely instead of claiming that the build completed with zero warnings.
- If no commit was requested, perform build validation only and do not run tests.
- If test code changed, run only the directly affected test or focused test group. An explicit user request to test also overrides the build-only rule.
- Tests are otherwise run only as a pre-commit gate.
- When the user requests a commit, first build all affected available targets successfully with zero errors and zero warnings. Only when the change affects core functionality, add or update the smallest relevant regression test and run the affected tests before committing.
- Core functionality includes primary workflows, persistent or shared state, data integrity, provider or protocol behavior, authorization, security boundaries, and cross-component lifecycle behavior.
- Do not add or run tests for minor copy, styling, layout polish, comments, documentation, naming, formatting, or mechanical non-core changes.
- Broaden the test run only when a core change crosses multiple subsystems or the user explicitly requests it.
- Required test runs must finish with zero failures, zero errors, and zero warnings.
- Report only validation actually performed; a successful build does not prove runtime, UX, device, provider, migration, or performance behavior.

## Review

- Review is read-only unless fixes are explicitly requested.
- Confirm each finding against the current baseline, intended contract, and a realistic execution path.
- When fixing review findings, address only confirmed root-cause P0/P1 defects and P2 defects that seriously affect user experience.
- Ignore minor P2, P3, style-only, speculative, adversarial, and excessively marginal cases unless explicitly included.
- Every accepted finding must be fixed at its root cause without fallback logic or unrelated refactoring.
- Report findings by severity with concrete impact and evidence.

## Git and Handoff

- Branch creation, staging, committing, pushing, PR creation, review replies, merging, and branch deletion each require explicit authorization.
- Before a requested commit, inspect the complete tracked, staged, and untracked diff, then run the required build and any tests required above.
- Keep commits focused and use one concise sentence for each commit message to describe the changes in the final net diff.
- Write pull request descriptions from the final net diff, with concrete details about the changes made and validation performed. Do not include intermediate work that was later removed or claims unsupported by the final diff and recorded validation.
- Do not alter stashes, rewrite history, discard user work, or use destructive Git operations without explicit authorization.
- Keep handoff concise: result, root cause or design seam, files changed, validation performed, and real remaining limitations.

## For This Project

- Use XcodeBuildMCP for all Xcode project, build, run, test, simulator, UI automation, and debugging operations. Use command-line Xcode tools only when the MCP is unavailable or does not expose the required capability.
- Refer to Apple’s official documentation, follow Apple Human Interface Guidelines for user-facing behavior, and use current Apple engineering best practices for implementation.
- Use English for source code, identifiers, comments, documentation, logs, and other developer-facing or model-facing text. Localize user-facing text through the project's existing localization resources.
- Treat current source, package manifests, and `Voice Chat.xcodeproj/project.pbxproj` as the source of truth.
- Follow the surrounding app or local-package style; do not mass-format vendored packages.
- Keep Xcode group, target, Sources/Resources phase, and package wiring correct for file changes.
- Preserve committed `Package.resolved` files unless dependency work is requested.
- Build shared changes cleanly on every affected supported Apple platform available in the environment.
- Treat provider/protocol logic, SwiftData persistence, tool authorization/execution, shared rendering, and voice/audio lifecycle as core functionality.
- Update every existing localization when user-visible text changes.
- Keep DerivedData and build caches in a task-specific directory under `/private/tmp`. Remove caches and other temporary artifacts created by the task when the work is complete.
