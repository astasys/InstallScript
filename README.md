# [Odoo](https://www.odoo.com "Odoo's Homepage") Install Script

This script is based on the install script from André Schenkels (https://github.com/aschenkels-ictstudio/openerp-install-scripts)
but goes a bit further and has been improved. This script will also give you the ability to define an xmlrpc_port in the .conf file that is generated under /etc/
This script can be safely used in a multi-odoo code base server because the default Odoo port is changed BEFORE the Odoo is started.

## Installing Nginx
```INSTALL_NGINX``` is ```True``` by default, so Odoo runs behind Nginx with ```proxy_mode``` enabled and the ```/websocket``` route proxied to the gevent port. This needs workers: keep ```WORKER_COUNT``` above 0, otherwise you will get connection loss issues. Look at [the deployment guide from Odoo](https://www.odoo.com/documentation/19.0/administration/on_premise/deploy.html) on how to size workers.

## Installation procedure

##### 1. Download the script:
```
sudo wget https://raw.githubusercontent.com/astasys/InstallScript/19.0-asta-custom/odoo_install.sh
```
##### 2. Modify the parameters as you wish.
There are a few things you can configure, this is the most used list:<br/>
```OE_USER``` will be the username for the system user.<br/>
```GENERATE_RANDOM_PASSWORD``` if this is set to ```True``` the script will generate a random password, if set to ```False```we'll set the password that is configured in ```OE_SUPERADMIN```. By default the value is ```True``` and the script will generate a random and secure password.<br/>
```INSTALL_WKHTMLTOPDF``` set to ```False``` if you do not want to install Wkhtmltopdf, if you want to install it you should set it to ```True```.<br/>
```OE_PORT``` is the port where Odoo should run on, for example 8069.<br/>
```OE_VERSION``` is the Odoo version to install, for example ```19.0``` for Odoo V19.<br/>
```IS_ENTERPRISE``` will install the Enterprise version on top of ```19.0``` if you set it to ```True```, set it to ```False``` if you want the community version of Odoo 19. The Enterprise install also adds the ```pgvector``` PostgreSQL extension, which the Odoo 19 AI features need.<br/>
```OE_ENTERPRISE_REPO``` is the Git repository the Enterprise code is cloned from. You need read access to it.<br/>
```INSTALL_POSTGRESQL_SIXTEEN``` installs PostgreSQL 16 from the official PostgreSQL apt repository when ```True```, otherwise the distribution default is used.<br/>
```OE_SUPERADMIN``` is the master password for this Odoo installation.<br/>
```INSTALL_NGINX``` is set to ```True``` by default. Set this to ```False``` if you do not want to install Nginx.<br/>
```GEVENT_PORT``` is the port of the Odoo gevent (websocket) worker, 8072 by default. Odoo 19 no longer recognises the old ```longpolling_port``` option.<br/>
```WORKER_COUNT``` is the number of Odoo workers written to the config file. Keep it above 0 when Nginx is used.<br/>
```TIMEZONE``` is the server timezone, ```Asia/Hong_Kong``` by default.<br/>
```LOG_RETENTION_DAYS``` is how many days of Odoo log files are kept, ```30``` by default. The log is rotated every day.<br/>
```WEBSITE_NAME``` Set the website name here for nginx configuration<br/>
```ENABLE_SSL``` Set this to ```True``` to install [certbot](https://github.com/certbot/certbot) and configure nginx with https using a free Let's Encrypted certificate<br/>
```ADMIN_EMAIL``` Email is needed to register for Let's Encrypt registration. Replace the default placeholder with an email of your organisation.<br/>
```INSTALL_NGINX``` and ```ENABLE_SSL``` must be set to ```True``` and the placeholder in ```ADMIN_EMAIL``` must be replaced with a valid email address for certbot installation<br/>
  _By enabling SSL though Let's Encrypt you agree to the following [policies](https://www.eff.org/code/privacy/policy)_ <br/>

#### 3. Make the script executable
```
sudo chmod +x odoo_install.sh
```
##### 4. Execute the script:
```
sudo ./odoo_install.sh
```

## What the script sets up
- Odoo runs from a Python virtual environment in ```/odoo/venv```, so nothing is installed into the system Python.
- Odoo is managed by systemd: ```sudo systemctl start|stop|restart odoo-server```.
- With Nginx, Odoo only listens on ```127.0.0.1``` (```http_interface```), so ports 8069 and 8072 are not reachable from the network and all traffic goes through Nginx on 80/443. To reach Odoo directly for debugging, use an SSH tunnel: ```ssh -L 8069:127.0.0.1:8069 user@server```. Without Nginx, Odoo listens on all interfaces.
- The PostgreSQL role is created with ```CREATEDB``` but without ```SUPERUSER```, and the Odoo system user is not added to the sudo group.
- wkhtmltopdf 0.12.6.1-3 (patched Qt) is installed from the [wkhtmltopdf packaging releases](https://github.com/wkhtmltopdf/packaging/releases/tag/0.12.6.1-3), for amd64 and arm64. There is no Ubuntu 24.04 build, the jammy build is used.
- Chinese fonts are installed so that PDF reports render Chinese text.
- The Odoo log in ```/var/log/odoo``` is rotated every day by logrotate (```/etc/logrotate.d/odoo-server```): one file per day named after the day it covers, for example ```odoo-server.log-20260919```, 30 days kept, older files gzip-compressed (read them with ```zless``` or ```zgrep```). Odoo does not need a restart when the log is rotated.

## Versions
The script targets **Ubuntu 24.04 LTS (Noble Numbat)** on amd64 or arm64.

Some versions are fixed by the script, the others are whatever the package repositories provide on the day of the install, so patch versions move over time. The versions below were recorded from a clean install on 2026-09-20.

| Component | Version installed | Source | Fixed by the script? |
|---|---|---|---|
| Operating system | Ubuntu 24.04 LTS | | Yes, this is the supported target |
| Odoo | 19.0, latest commit of the branch | [odoo/odoo](https://github.com/odoo/odoo/tree/19.0) on GitHub | Branch fixed by ```OE_VERSION``` |
| Python | 3.12.3 | Ubuntu repository | No. Ubuntu 24.04 stays on 3.12. Odoo 19 needs 3.10 or later |
| pip | 24.0 | Ubuntu repository | No |
| PostgreSQL server | 16.15 | [PostgreSQL apt repository](https://apt.postgresql.org) | Major version 16 fixed. Odoo 19 needs 13 or later |
| pgvector, Enterprise only | 0.8.6 | PostgreSQL apt repository | No. Needs PostgreSQL 15 or later |
| libpq, PostgreSQL client library | 18.6 | PostgreSQL apt repository | No. That repository always ships the newest libpq, which works with a version 16 server |
| Nginx | 1.24.0 | Ubuntu repository | No |
| wkhtmltopdf | 0.12.6.1-3 with patched Qt, jammy build | [wkhtmltopdf packaging](https://github.com/wkhtmltopdf/packaging/releases/tag/0.12.6.1-3) on GitHub | Yes, ```WKHTMLTOX_VERSION``` |
| Node.js | 18.19.1 | Ubuntu repository | No |
| npm | 9.2.0 | Ubuntu repository | No |
| rtlcss | latest | npm registry | No |
| Git | 2.43.0 | Ubuntu repository | No |
| GCC, used to build Python packages | 13.2.0 | Ubuntu repository | No |
| logrotate | 3.21.0 | Ubuntu repository | No |
| Certbot, only with ```ENABLE_SSL``` | latest | snap | No |
| Python packages | see below | PyPI | Yes, pinned by the Odoo ```requirements.txt``` |

<details>
<summary>System libraries and fonts</summary>

| Package | Version |
|---|---|
| libpq-dev | 18.6 |
| libxslt1-dev | 1.1.39 |
| libzip-dev | 1.7.3 |
| libldap2-dev | 2.6.10 |
| libsasl2-dev | 2.1.28 |
| libjpeg-dev | 8c |
| libpng-dev | 1.6.43 |
| libmagic1 | 5.45 |
| node-less | 3.13.0 |
| fonts-wqy-zenhei | 0.9.45 |
| fonts-wqy-microhei | 0.2.0-beta |
| fonts-arphic-ukai | 0.2.20080216.2 |
| fonts-arphic-uming | 0.2.20080216.2 |

</details>

<details>
<summary>Python packages in the virtual environment</summary>

These are the versions the Odoo 19.0 ```requirements.txt``` pins for Python 3.12. ```pytz``` and ```lxml-html-clean``` are left unpinned by Odoo, and ```phonenumbers``` is added unpinned by this script, so those three follow PyPI.

| Package | Version | Package | Version | Package | Version |
|---|---|---|---|---|---|
| asn1crypto | 1.5.1 | libsass | 0.22.0 | python-dateutil | 2.8.2 |
| Babel | 2.10.3 | lxml | 5.2.1 | python-ldap | 3.4.4 |
| cbor2 | 5.6.2 | lxml-html-clean | 0.4.4 | python-magic | 0.4.27 |
| chardet | 5.2.0 | MarkupSafe | 2.1.5 | python-stdnum | 1.19 |
| cryptography | 42.0.8 | num2words | 0.5.13 | pytz | 2026.3.post1 |
| docutils | 0.20.1 | ofxparse | 0.21 | pyusb | 1.2.1 |
| freezegun | 1.2.1 | openpyxl | 3.1.2 | qrcode | 7.4.2 |
| geoip2 | 2.9.0 | passlib | 1.7.4 | reportlab | 4.1.0 |
| gevent | 24.2.1 | phonenumbers | 9.0.39 | requests | 2.31.0 |
| greenlet | 3.0.3 | Pillow | 10.2.0 | rjsmin | 1.2.0 |
| idna | 3.6 | polib | 1.1.1 | urllib3 | 2.0.7 |
| Jinja2 | 3.1.2 | psutil | 5.9.8 | vobject | 0.9.6.1 |
| Werkzeug | 3.0.1 | psycopg2 | 2.9.9 | xlrd | 2.0.1 |
| XlsxWriter | 3.1.9 | pyopenssl | 24.1.0 | xlwt | 1.3.0 |
| zeep | 4.2.1 | PyPDF2 | 2.12.1 | pyserial | 3.5 |

The Enterprise install adds ```pdfminer.six```, ```dbfread```, ```ebaysdk``` and ```firebase_admin```, unpinned.

</details>

## Testing the script
The ```test_install``` folder contains a Docker setup that runs the script in a clean Ubuntu 24.04 container. See [test_install/README.md](test_install/README.md).

## Where should I host Odoo?
There are plenty of great services that offer good hosting. The script has been tested with a few major players such as [Google Cloud](https://cloud.google.com/), [Hetzner](https://www.hetzner.com/), [Amazon AWS](https://aws.amazon.com/) and [DigitalOcean](https://www.digitalocean.com/products/droplets/).
If you'd like you can use my [DigitalOcean referral link](https://m.do.co/c/d605cc420682) which gives you a 200$ voucher for free for the first 60 days.

## Minimal server requirements
While technically you can run an Odoo instance on 1GB (1024MB) of RAM it is absolutely not advised. A Linux instance typically uses 300MB-500MB and the rest has to be split among Odoo, postgreSQL and others. If you install an Odoo you should make sure to use at least 2GB of RAM. This script might fail with less resources too.
There are known issues on DigitalOcean for example where the installation crashes on 1GB RAM machines. See https://github.com/Yenthe666/InstallScript/issues/243

