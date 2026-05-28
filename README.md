# Simple VPS

## Overview
Simple VPS is a lightweight Bash-based VPS management toolkit.

Core features:
- Install and manage Nginx, PHP-FPM, MariaDB/MySQL.
- Adminer setup and management (install, port change, basic auth, enable/disable).
- Database management (status/start/stop/restart/login/create database + optional dedicated user).
- Site creation:
  - New WordPress site (optional auto DB/user creation)
  - New blank PHP site
  - New blank Laravel-style site
- Firewall management with firewalld:
  - Install/start/stop/restart/status
  - Allow/remove ports
  - Allow list / blacklist IP rules
  - Quick allow HTTP/HTTPS
  - Reset zone rules to default

## How to install

### Option 1: One-line bootstrap (recommended)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hoangpham5694/LEMP-script/master/builds/get-simple-vps.sh)
```

### Option 2: Run from local files
```bash
sudo bash src/install.sh
```

During installation, the script asks for:
- PHP version
- Database engine (MariaDB or MySQL)
- Database version

After installation, command `simple-vps` is installed into `/usr/local/bin/simple-vps`.

## How to use
Run the management menu:
```bash
simple-vps
```

Main menu includes:
- Manage Nginx
- Manage Database
- Manage Adminer
- Create site
- Firewall

Examples:
- Create a WordPress site: `Create site -> New wordpress site`
- Create DB + user manually: `Manage Database -> Create database`
- Setup Adminer access: `Manage Adminer -> Install Adminer`
- Open HTTP/HTTPS quickly: `Firewall -> Allow HTTP/HTTPS quick`

## Device support
This project is designed for Linux VPS/server environments.

Supported package ecosystems:
- Debian/Ubuntu (`apt`)
- RHEL-family/CentOS/Rocky/Alma/Oracle Linux/Fedora (`dnf`)

Not supported:
- Windows (native)
- macOS (native)
- Non-systemd Linux distributions

For best experience, use a fresh Linux VPS with:
- Root or sudo privileges
- Internet access for package downloads
- systemd enabled

## External software download sources
The scripts download some external software/components from these sources:

- WordPress: `https://wordpress.org/latest.tar.gz`
- Adminer: `https://www.adminer.org/#download`
- MariaDB repository setup script: `https://downloads.mariadb.com/MariaDB/mariadb_repo_setup`
- PHP package repository key (Debian): `https://packages.sury.org/php/apt.gpg`
- Remi PHP repository RPM (RHEL family): `https://rpms.remirepo.net/enterprise/`
- MySQL community repository RPM (RHEL family): `https://repo.mysql.com/`
- PHPMemcachedAdmin: `https://github.com/elijaa/phpmemcachedadmin`
- phpRedisAdmin: `https://github.com/erikdubbelboer/phpRedisAdmin`
- phpSysInfo: `https://github.com/phpsysinfo/phpsysinfo`
- Opcache Dashboard (opcache-gui): `https://github.com/amnuts/opcache-gui`

Notes:
- OS packages for Nginx, PHP-FPM, MariaDB/MySQL, Redis, Memcached, and Pureftpd are installed from your system package manager repositories (`apt`/`dnf`).
- Review and pin versions/sources as needed for your production environment.
