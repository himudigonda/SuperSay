# Contributing to SuperSay

## Development Philosophy

1.  **Privacy First**: No telemetry, no cloud calls.
2.  **Native Feel**: The app should feel like it belongs on macOS (Human Interface Guidelines).
3.  **Clean Code**:
    *   **Swift**: Use MVVM. No logic in Views.
    *   **Python**: Type hints are mandatory. Use `ruff` for linting.

## Pull Request Process

1.  **Fork** the repo.
2.  **Branch** off `main`. Name it `feature/your-feature` or `fix/your-bug`.
3.  **Test**:
    *   Ensure the backend compiles (`./scripts/compile_backend.sh`).
    *   Ensure Xcode builds without warnings.
4.  **Submit** PR with a screenshot (for UI changes) or logs (for logic changes).

## Reporting Issues

Please use the [Bug Report Template](../.github/ISSUE_TEMPLATE/bug_report.md) and include:
*   macOS Version
*   Python Version
*   Console Logs (search "SuperSay" in Console.app)
