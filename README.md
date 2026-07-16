# nsupdate with INWX TOTP 2FA

This repository is a modified fork of
[`chrisb86/nsupdate`](https://github.com/chrisb86/nsupdate).

It updates INWX `A` and `AAAA` DNS records through the DomRobot XML-RPC API and adds automated TOTP-based two-factor authentication.

The original copyright remains with Christian Busch. Modifications in this fork were made in 2026 by Icki153.

## Features

* Updates existing INWX `A` and `AAAA` records
* Automatically creates a record when it does not yet exist
* Supports INWX TOTP two-factor authentication
* Uses a session-based login flow
* Validates INWX API response codes in addition to HTTP errors
* Supports global and per-record configuration overrides
* Escapes XML values before sending them to the API
* Removes temporary session and response files after execution
* Supports execution through cron or Docker

## Authentication flow

The original script sends the username and password with each `nameserver.*` request.

This fork uses the session-based INWX API flow:

1. Call `account.login` with username and password
2. Detect whether the account requires TOTP authentication
3. Generate the current TOTP from the configured shared secret
4. Call `account.unlock` with the generated TOTP
5. Query the current DNS record using `nameserver.info`
6. Create a missing record using `nameserver.createRecord`
7. Update an existing record using `nameserver.updateRecord`
8. Call `account.logout`
9. Remove temporary cookie and response files

All DNS operations are performed inside the same authenticated cookie session.

## Requirements

The following programs are required:

* POSIX-compatible shell
* `curl`
* `xmllint`
* `mktemp`
* `oathtool` when the INWX account uses TOTP 2FA

On Debian or Ubuntu:

```sh
sudo apt update
sudo apt install git curl libxml2-utils oathtool
```

`xmllint` is provided by the `libxml2-utils` package.

## Installation from GitHub

Clone the repository:

```sh
git clone https://github.com/Icki153/nsupdate.git
cd nsupdate
```

Install the script:

```sh
sudo install -m 0755 nsupdate.sh /usr/local/bin/nsupdate.sh
```

Create the configuration and log directories:

```sh
sudo mkdir -p /usr/local/etc/nsupdate/conf.d
sudo mkdir -p /var/log/nsupdate
```

Copy the example configuration files:

```sh
sudo cp nsupdate/nsupdate.conf.dist \
  /usr/local/etc/nsupdate/nsupdate.conf

sudo cp nsupdate/conf.d/sub.example.com_AAAA.conf.dist \
  /usr/local/etc/nsupdate/conf.d/sub.example.com_AAAA.conf
```

Protect the configuration files:

```sh
sudo chmod 600 \
  /usr/local/etc/nsupdate/nsupdate.conf \
  /usr/local/etc/nsupdate/conf.d/*.conf
```

## Installation from a ZIP archive

Alternatively, download the repository as a ZIP archive from GitHub.

Extract the archive:

```sh
unzip nsupdate-main.zip
cd nsupdate-main
```

Then install the files:

```sh
sudo install -m 0755 nsupdate.sh /usr/local/bin/nsupdate.sh

sudo mkdir -p \
  /usr/local/etc/nsupdate/conf.d \
  /var/log/nsupdate

sudo cp nsupdate/nsupdate.conf.dist \
  /usr/local/etc/nsupdate/nsupdate.conf

sudo cp nsupdate/conf.d/sub.example.com_AAAA.conf.dist \
  /usr/local/etc/nsupdate/conf.d/sub.example.com_AAAA.conf

sudo chmod 600 \
  /usr/local/etc/nsupdate/nsupdate.conf \
  /usr/local/etc/nsupdate/conf.d/*.conf
```

## Global configuration

Edit:

```text
/usr/local/etc/nsupdate/nsupdate.conf
```

Example:

```sh
NSUPDATE_INWX_USER="api-user"
NSUPDATE_INWX_PASSWORD="api-password"
NSUPDATE_INWX_SHARED_SECRET="BASE32SECRETFROMTHE2FAQRCODE"
```

The shared secret is the permanent Base32 value behind the 2FA QR code.

It is not the changing six-digit code displayed by an authenticator application.

Additional example settings:

```sh
NSUPDATE_INWX_API="https://api.domrobot.com/xmlrpc/"
NSUPDATE_TMP_DIR="/tmp"
NSUPDATE_LOG_DIR="/var/log/nsupdate"
VERBOSE="false"
```

Use the values already provided in `nsupdate.conf.dist` unless they need to be changed.

## Record configuration

Create one configuration file for each DNS record inside:

```text
/usr/local/etc/nsupdate/conf.d/
```

Example:

```text
/usr/local/etc/nsupdate/conf.d/home.example.com_A.conf
```

Contents:

```sh
MAIN_DOMAIN="example.com"
DOMAIN="home.example.com"
RECORD_TYPE="A"
RECORD_TTL="300"
```

For an IPv6 record:

```sh
MAIN_DOMAIN="example.com"
DOMAIN="home.example.com"
RECORD_TYPE="AAAA"
RECORD_TTL="300"
```

`MAIN_DOMAIN` must already exist as a DNS zone in the INWX account.

The individual host record may be missing. In that case, the script creates it automatically.

## Per-record credentials

Global credentials can be overridden inside an individual record configuration file:

```sh
INWX_USER="different-api-user"
INWX_PASSWORD="different-api-password"
INWX_SHARED_SECRET="DIFFERENTBASE32SECRET"
```

This can be useful when different records belong to different INWX accounts or sub-accounts.

## Alternative TOTP command

Instead of storing the shared secret directly in the configuration, a trusted command can be used to generate the current TOTP:

```sh
INWX_TOTP_COMMAND='pass otp inwx/api'
```

The command must print only the current TOTP code.

The configuration files are sourced as shell code. They must therefore only be writable by trusted administrators.

## Manual test

Run the script manually:

```sh
sudo /usr/local/bin/nsupdate.sh
```

For verbose output, set this in the global configuration:

```sh
VERBOSE="true"
```

Then run the script again:

```sh
sudo /usr/local/bin/nsupdate.sh
```

## Cron

Edit the root crontab:

```sh
sudo crontab -e
```

Run the script every five minutes:

```cron
*/5 * * * * /usr/local/bin/nsupdate.sh >/dev/null 2>&1
```

To retain the output in a log file:

```cron
*/5 * * * * /usr/local/bin/nsupdate.sh >>/var/log/nsupdate/cron.log 2>&1
```

Make sure the cron user can read the configuration files.

## Updating the installation

Open the cloned repository:

```sh
cd ~/nsupdate
```

Download the latest changes from the `main` branch:

```sh
git switch main
git pull origin main
```

Reinstall the updated script:

```sh
sudo install -m 0755 nsupdate.sh /usr/local/bin/nsupdate.sh
```

Existing production configuration files under `/usr/local/etc/nsupdate/` are not overwritten by this command.

Compare new example configuration options manually:

```sh
diff -u \
  /usr/local/etc/nsupdate/nsupdate.conf \
  nsupdate/nsupdate.conf.dist
```

Do not blindly replace the production configuration because it contains the real credentials.

## Security notes

Automated TOTP authentication requires access to:

* the INWX username
* the INWX password
* the TOTP shared secret or another method of generating the TOTP

The host running the script therefore has access to both authentication factors.

Recommended precautions:

* Use a dedicated INWX sub-account
* Grant only the required DNS permissions
* Restrict the account to the required zones where possible
* Protect all configuration files with mode `0600`
* Do not commit production configuration files
* Do not print passwords, shared secrets or TOTP values in logs
* Restrict administrative access to the host
* Keep the operating system and installed packages updated

## Compatibility

The fork retains the original global and per-record override model.

It also accepts the legacy configuration names:

```sh
TYPE="A"
TTL="300"
```

The preferred names are:

```sh
RECORD_TYPE="A"
RECORD_TTL="300"
```

Unlike the original fallback behavior, `xmllint` is mandatory. Session login, record detection and API error validation require reliable XML parsing.

## Troubleshooting

### Invalid username or password

Verify the configured username and password and make sure the account has access to the required DNS zone.

### TOTP unlock failed

Verify that:

* the shared secret is the Base32 secret from the INWX 2FA setup
* the secret does not contain spaces
* the system clock is correct
* `oathtool` is installed
* the generated code matches the authenticator application

Test the TOTP locally:

```sh
oathtool --totp -b "YOURBASE32SECRET"
```

Do not publish the shared secret or include it in logs.

### Record not found

A missing host record is normally created automatically.

However, the DNS zone specified by `MAIN_DOMAIN` must already exist in the INWX account.

Example:

```sh
MAIN_DOMAIN="example.com"
DOMAIN="home.example.com"
```

The zone `example.com` must exist. The record `home.example.com` may be created by the script.

### Permission denied

Check the permissions:

```sh
sudo ls -l /usr/local/etc/nsupdate/
sudo ls -l /usr/local/etc/nsupdate/conf.d/
```

The files should normally be owned by `root` and use mode `0600`.

### No update is performed

Enable verbose output:

```sh
VERBOSE="true"
```

Run manually:

```sh
sudo /usr/local/bin/nsupdate.sh
```

The public IP may already match the DNS record.

## License

This repository is a modified fork of
[`chrisb86/nsupdate`](https://github.com/chrisb86/nsupdate).

The original project was created by Christian Busch and is distributed under the MIT License.

The original copyright and permission notice are retained in the repository's [`LICENSE`](LICENSE) file.

Modifications in this fork were made in 2026 by Icki153.

See [`LICENSE`](LICENSE) for the complete license text.

