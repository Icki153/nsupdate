## 2026-07-16

- Create missing A/AAAA records automatically on first run via `nameserver.createRecord`.
- Treat an empty `nameserver.info` result as a missing record instead of a fatal error.

# Changelog

## 2FA fork - 2026-07-16

- Added session-based `account.login` and `account.logout`.
- Added TOTP 2FA detection and `account.unlock`.
- Added `NSUPDATE_INWX_SHARED_SECRET` and per-record `INWX_SHARED_SECRET`.
- Added optional `INWX_TOTP_COMMAND`.
- Added cookie-jar handling with mode-0600 temporary files.
- Added XML escaping and XML-RPC response-code validation.
- Made `xmllint` mandatory for reliable API processing.
- Updated Docker image with `oathtool`.
- Updated example configuration and documentation.
