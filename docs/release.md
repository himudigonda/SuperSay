# 🚀 Release Process

1.  **Version Bump:**
    -   Update `version` in `backend/pyproject.toml`.
    -   Update `MARKETING_VERSION` in Xcode Project settings.
2.  **Compile Backend:**
    -   Run `make backend`. This updates `Resources/SuperSayServer.zip`.
3.  **Build Release App:**
    -   Run `make release VERSION=1.0.x`.
4.  **Verification:**
    -   Install the generated DMG.
    -   Test the `xattr` command logic.
    -   Verify "The Vault" migrates existing data correctly.
5.  **GitHub Release:**
    -   Use `ship.sh` to automate tagging and asset upload to GitHub.
