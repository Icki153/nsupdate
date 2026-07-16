# nsupdate with INWX TOTP 2FA

This fork of `chrisb86/nsupdate` updates INWX `A` and `AAAA` records through the DomRobot XML-RPC API and adds automated TOTP-based two-factor authentication.

## What changed

The original script sends username and password with each `nameserver.*` request. This fork uses the session-based API flow:

1. `account.login` with username and password
2. Detect the requested 2FA method
3. Generate a TOTP from the configured shared secret
4. `account.unlock` with the current TOTP
5. Run `nameserver.info` and either create a missing record with `nameserver.createRecord` or update an existing record with `nameserver.updateRecord` in the same cookie session
6. `account.logout` and remove temporary credentials/session files

API-level errors are validated in addition to HTTP errors. XML values are escaped before use.

## Requirements

- POSIX-compatible shell
- `curl`
- `xmllint` (`libxml2-utils` on Debian/Ubuntu)
- `mktemp`
- `oathtool` when the INWX account uses TOTP 2FA (`oathtool` package on Debian/Ubuntu)

Example:

```sh
sudo apt update
sudo apt install curl libxml2-utils oathtool
```

## Installation

```sh
sudo install -m 0755 nsupdate.sh /usr/local/bin/nsupdate.sh
sudo mkdir -p /usr/local/etc/nsupdate/conf.d /var/log/nsupdate
sudo cp nsupdate/nsupdate.conf.dist /usr/local/etc/nsupdate/nsupdate.conf
sudo cp nsupdate/conf.d/sub.example.com_AAAA.conf.dist \
  /usr/local/etc/nsupdate/conf.d/sub.example.com_AAAA.conf
sudo chmod 600 /usr/local/etc/nsupdate/nsupdate.conf \
  /usr/local/etc/nsupdate/conf.d/*.conf
```

Edit `/usr/local/etc/nsupdate/nsupdate.conf`:

```sh
NSUPDATE_INWX_USER="api-user"
NSUPDATE_INWX_PASSWORD="api-password"
NSUPDATE_INWX_SHARED_SECRET="BASE32SECRETFROMTHE2FAQRCODE"
```

The shared secret is the permanent Base32 value behind the 2FA QR code. It is not the changing six-digit authenticator code.

Edit a record file:

```sh
MAIN_DOMAIN="example.com"
DOMAIN="home.example.com"
RECORD_TYPE="A"
RECORD_TTL="300"
```

Run manually:

```sh
sudo /usr/local/bin/nsupdate.sh
```

Cron every five minutes:

```cron
*/5 * * * * /usr/local/bin/nsupdate.sh >/dev/null 2>&1
```

## Alternative TOTP command

Instead of storing the secret directly in the config, configure a trusted command that prints the current TOTP:

```sh
INWX_TOTP_COMMAND='pass otp inwx/api'
```

The configuration files are sourced as shell code and therefore must only be writable by trusted administrators.

## Security notes

Automation requires access to both the password and the material needed to generate the second factor. Prefer a dedicated INWX sub-account with only the DNS permissions and zones it needs. Protect all configuration files with mode `0600`.

## Compatibility

The fork retains the original global/per-record override model and accepts the legacy `TYPE` and `TTL` names. Unlike the original fallback behavior, `xmllint` is mandatory because session login and API error validation require XML parsing.

## License

License
nsupdate is distributed under the MIT license, which is similar in effect to the BSD license.

Copyright 2013 Christian Busch (http://github.com/chrisb86)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
