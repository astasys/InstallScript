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

## Testing the script
The ```test_install``` folder contains a Docker setup that runs the script in a clean Ubuntu 24.04 container. See [test_install/README.md](test_install/README.md).

## Where should I host Odoo?
There are plenty of great services that offer good hosting. The script has been tested with a few major players such as [Google Cloud](https://cloud.google.com/), [Hetzner](https://www.hetzner.com/), [Amazon AWS](https://aws.amazon.com/) and [DigitalOcean](https://www.digitalocean.com/products/droplets/).
If you'd like you can use my [DigitalOcean referral link](https://m.do.co/c/d605cc420682) which gives you a 200$ voucher for free for the first 60 days.

## Minimal server requirements
While technically you can run an Odoo instance on 1GB (1024MB) of RAM it is absolutely not advised. A Linux instance typically uses 300MB-500MB and the rest has to be split among Odoo, postgreSQL and others. If you install an Odoo you should make sure to use at least 2GB of RAM. This script might fail with less resources too.
There are known issues on DigitalOcean for example where the installation crashes on 1GB RAM machines. See https://github.com/Yenthe666/InstallScript/issues/243

