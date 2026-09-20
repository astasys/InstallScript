#!/bin/bash
################################################################################
# Script for installing Odoo 19 on Ubuntu 24.04 (could be used for other version too)
# Author: Yenthe Van Ginneken
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo-install.sh
# Execute the script to install Odoo:
# ./odoo-install
################################################################################

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
# Python virtual environment used to run Odoo (keeps pip packages away from the system Python, PEP 668)
OE_VENV="$OE_HOME/venv"
# Set to true if you want to install it, false if you don't need it or have it already installed.
INSTALL_WKHTMLTOPDF="True"
# Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
# Choose the Odoo version which you want to install. For example: 19.0, 18.0 or saas-22. When using 'master' the master version will be installed.
# IMPORTANT! This script contains extra libraries that are specifically needed for Odoo 19.0
OE_VERSION="19.0"
# Set this to True if you want to install the Odoo enterprise version!
IS_ENTERPRISE="False"
# Git repository the Odoo enterprise code is cloned from (needs read access)
OE_ENTERPRISE_REPO="https://www.github.com/astasys/enterprise"
# Installs postgreSQL V16 from the official PostgreSQL apt repository instead of the distribution default
INSTALL_POSTGRESQL_SIXTEEN="True"
# Set this to True if you want to install Nginx!
INSTALL_NGINX="True"
# Set the superadmin password - if GENERATE_RANDOM_PASSWORD is set to "True" we will automatically generate a random password, otherwise we use this one
OE_SUPERADMIN="admin"
# Set to "True" to generate a random password, "False" to use the variable in OE_SUPERADMIN
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
# Set the website name
WEBSITE_NAME="_"
# Set the Odoo gevent (websocket) port. This option was called longpolling_port before Odoo 16,
# the old name is no longer recognised by Odoo 19.
GEVENT_PORT="8072"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate
ADMIN_EMAIL="odoo@example.com"
# Number of Odoo workers. Keep this above 0 when Nginx is used: the /websocket location
# is proxied to GEVENT_PORT, which is only served in multi-worker mode.
WORKER_COUNT=4
# Server timezone
TIMEZONE="Asia/Hong_Kong"
# The Odoo log is rotated every day, this is how many days of log files are kept
LOG_RETENTION_DAYS="30"
# wkhtmltopdf build with patched Qt, the version recommended by Odoo (needed for headers and footers)
WKHTMLTOX_VERSION="0.12.6.1-3"

#--------------------------------------------------
# Helpers
#--------------------------------------------------
# Stop the script with a clear message, for steps the install cannot continue without.
# Without this the script would carry on and report success after e.g. a failed git clone.
die() {
  echo -e "\nERROR: $*" >&2
  echo "The installation did NOT complete. Fix the problem above and run the script again." >&2
  exit 1
}

# Run a command up to 3 times, for steps that depend on the network (apt mirrors, GitHub, PyPI)
retry() {
  local attempt
  for attempt in 1 2 3; do
    "$@" && return 0
    echo "Attempt $attempt/3 failed: $*"
    sleep 5
  done
  return 1
}

# apt-get wrapper: always non-interactive, so the script never stops to ask a question
# (Ubuntu 22.04+ otherwise shows needrestart / tzdata dialogs during installs and upgrades)
apt_get() {
  retry sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -y -o Acquire::Retries=3 "$@" \
    || die "apt-get $* failed"
}

# pip inside the Odoo virtualenv, run as the Odoo user so the venv stays owned by that user
venv_pip() {
  retry sudo -H -u "$OE_USER" "$OE_VENV/bin/pip" "$@" || die "pip $* failed"
}

# True when systemd is running. False inside a plain Docker container (see test_install/)
has_systemd() {
  [ -d /run/systemd/system ]
}

##
###  WKHTMLTOPDF download link
## There is no wkhtmltopdf build for Ubuntu 24.04 (noble), the jammy build is the one to use there.
## Builds exist for amd64 and arm64. For a danger note refer to
## https://github.com/odoo/odoo/wiki/Wkhtmltopdf
case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
  amd64|x86_64)   ARCH_DEB="amd64";;
  arm64|aarch64)  ARCH_DEB="arm64";;
  *)              ARCH_DEB="$(dpkg --print-architecture 2>/dev/null || uname -m)";;
esac

if [[ "$(lsb_release -r -s)" == "24.04" ]]; then
  WKHTMLTOX_CODENAME="jammy"
else
  WKHTMLTOX_CODENAME="$(lsb_release -c -s)"
fi
WKHTMLTOX_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOX_VERSION}/wkhtmltox_${WKHTMLTOX_VERSION}.${WKHTMLTOX_CODENAME}_${ARCH_DEB}.deb"

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Update Server ----"
apt_get update
apt_get upgrade

#--------------------------------------------------
# Set Timezone
#--------------------------------------------------
echo -e "\n---- Set timezone $TIMEZONE ----"
if has_systemd; then
  sudo timedatectl set-timezone "$TIMEZONE"
else
  apt_get install tzdata
  sudo ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  echo "$TIMEZONE" | sudo tee /etc/timezone > /dev/null
fi

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
echo -e "\n---- Install PostgreSQL Server ----"
apt_get install curl gnupg lsb-release ca-certificates
if [ "$INSTALL_POSTGRESQL_SIXTEEN" = "True" ]; then
    echo -e "\n---- Installing postgreSQL V16 due to the user it's choise ----"
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --yes --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    apt_get update
    apt_get install postgresql-16
    PG_MAJOR="16"
else
    echo -e "\n---- Installing the default postgreSQL version based on Linux version ----"
    apt_get install postgresql postgresql-server-dev-all
    PG_MAJOR="$(pg_lsclusters --no-header | awk 'NR==1 {print $1}')"
fi

echo -e "\n---- Make sure PostgreSQL is running ----"
if has_systemd; then
  sudo systemctl start postgresql
else
  sudo service postgresql start
fi
for _ in $(seq 1 30); do
  sudo -u postgres pg_isready -q && break
  sleep 1
done

if [ "$IS_ENTERPRISE" = "True" ]; then
    # pgvector is needed by the AI features of Odoo Enterprise
    echo -e "\n---- Installing pgvector for Odoo Enterprise ----"
    apt_get install "postgresql-${PG_MAJOR}-pgvector"
    # Created in template1 so that every new database gets the extension
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;"
fi

echo -e "\n---- Creating the ODOO PostgreSQL User  ----"
# Create the role with CREATEDB (Odoo needs it to create/drop databases) but WITHOUT
# SUPERUSER. A superuser role can run 'COPY ... FROM PROGRAM', which lets anyone who
# reaches an Odoo admin turn SQL access into shell command execution as the postgres
# OS user. Keeping the role non-superuser closes that privilege-escalation path and
# matches Odoo's deployment guidance. See:
# https://www.odoo.com/documentation/19.0/administration/on_premise/deploy.html
sudo su - postgres -c "createuser -d -R -S $OE_USER" 2> /dev/null || true

echo -e "\n---- Create ODOO system user ----"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER

#--------------------------------------------------
# Install Dependencies
#--------------------------------------------------
echo -e "\n--- Installing Python 3 + pip3 --"
apt_get install python3 python3-pip
# libmagic1 is needed by python-magic, which is a requirement since Odoo 19
apt_get install git python3-cffi build-essential wget python3-dev python3-venv python3-wheel libpq-dev libxslt1-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools node-less libpng-dev libjpeg-dev libmagic1

echo -e "\n---- Installing nodeJS NPM and rtlcss for LTR support ----"
apt_get install nodejs npm
retry sudo npm install -g rtlcss \
  || echo "WARNING: rtlcss could not be installed, right-to-left languages will not render correctly."

#--------------------------------------------------
# Install Wkhtmltopdf if needed
#--------------------------------------------------
if [ "$INSTALL_WKHTMLTOPDF" = "True" ]; then
  echo -e "\n---- Install wkhtmltopdf $WKHTMLTOX_VERSION ($WKHTMLTOX_CODENAME build, $ARCH_DEB) ----"
  WKHTMLTOX_DEB="/tmp/$(basename "$WKHTMLTOX_URL")"
  if wget -q -O "$WKHTMLTOX_DEB" "$WKHTMLTOX_URL"; then
    # apt-get resolves the dependencies of the local .deb (fonts, libssl, ...)
    apt_get install "$WKHTMLTOX_DEB"
    sudo ln -sf /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
    sudo ln -sf /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage
  else
    echo "WARNING: could not download $WKHTMLTOX_URL"
    echo "WARNING: wkhtmltopdf is NOT installed, PDF reports will not work until you install it manually."
  fi
  rm -f "$WKHTMLTOX_DEB"
else
  echo -e "\n---- Wkhtmltopdf will not be installed at the user's choice ----"
fi

#--------------------------------------------------
# Install Chinese fonts
#--------------------------------------------------
echo -e "\n---- Install Chinese fonts ----"
apt_get install fonts-wqy-zenhei fonts-wqy-microhei fonts-arphic-ukai fonts-arphic-uming

echo -e "\n---- Create Log directory ----"
sudo mkdir -p /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

echo -e "\n---- Rotate the Odoo log daily, keep $LOG_RETENTION_DAYS days ----"
apt_get install logrotate
# Odoo has no log rotation of its own. It writes its log through a WatchedFileHandler, which
# reopens the file by itself once logrotate has renamed it. So a plain rename + create is enough:
# no copytruncate (which can lose lines) and no Odoo restart.
# dateyesterday: logrotate runs shortly after midnight, so the file it rotates holds yesterday's log.
# delaycompress: a worker may still write a few lines to the renamed file before it reopens.
cat <<EOF | sudo tee /etc/logrotate.d/${OE_CONFIG} > /dev/null
/var/log/${OE_USER}/*.log {
    daily
    rotate ${LOG_RETENTION_DAYS}
    dateext
    dateyesterday
    missingok
    notifempty
    compress
    delaycompress
    su ${OE_USER} ${OE_USER}
    create 640 ${OE_USER} ${OE_USER}
}
EOF

#--------------------------------------------------
# Install ODOO
#--------------------------------------------------
echo -e "\n==== Installing ODOO Server ===="
if [ -f "$OE_HOME_EXT/odoo-bin" ]; then
    echo "Odoo source already present in $OE_HOME_EXT, skipping the clone"
else
    retry sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/ \
      || die "Could not clone Odoo $OE_VERSION from GitHub"
fi

echo -e "\n---- Install python packages/requirements ----"
sudo -H -u $OE_USER python3 -m venv $OE_VENV || die "Could not create the Python virtualenv in $OE_VENV"
venv_pip install -r $OE_HOME_EXT/requirements.txt
# Extra: phonenumbers is needed for phone number validation/formatting
venv_pip install phonenumbers

if [ "$IS_ENTERPRISE" = "True" ]; then
    # Odoo Enterprise install!
    sudo su $OE_USER -c "mkdir -p $OE_HOME/enterprise/addons"

    if [ -d "$OE_HOME/enterprise/addons/.git" ]; then
        echo "Enterprise code already present in $OE_HOME/enterprise/addons, skipping the clone"
        GITHUB_RESPONSE=""
    else
        GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION $OE_ENTERPRISE_REPO "$OE_HOME/enterprise/addons" 2>&1)
    fi
    while [[ $GITHUB_RESPONSE == *"Authentication"* ]]; do
        echo "------------------------WARNING------------------------------"
        echo "Your authentication with Github has failed! Please try again."
        printf "In order to clone and install the Odoo enterprise version you \nneed to be an offical Odoo partner and you need access to\n$OE_ENTERPRISE_REPO.\n"
        echo "TIP: Press ctrl+c to stop this script."
        echo "-------------------------------------------------------------"
        echo " "
        GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION $OE_ENTERPRISE_REPO "$OE_HOME/enterprise/addons" 2>&1)
    done

    [ -d "$OE_HOME/enterprise/addons/.git" ] || die "Could not clone Odoo Enterprise from $OE_ENTERPRISE_REPO: $GITHUB_RESPONSE"

    echo -e "\n---- Added Enterprise code under $OE_HOME/enterprise/addons ----"
    echo -e "\n---- Installing Enterprise specific libraries ----"
    # num2words, ofxparse, psycopg2 and pyopenssl are already pinned in the Odoo requirements.txt.
    # Do not install them again unpinned, that would upgrade cryptography/pyopenssl past the supported versions.
    venv_pip install pdfminer.six dbfread ebaysdk firebase_admin
fi

echo -e "\n---- Create custom module directory ----"
sudo su $OE_USER -c "mkdir -p $OE_HOME/custom/addons"

echo -e "\n---- Setting permissions on home folder ----"
sudo chown -R $OE_USER:$OE_USER $OE_HOME

echo -e "* Create server config file"
if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
    echo -e "* Generating random admin password"
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi

if [ "$IS_ENTERPRISE" = "True" ]; then
    OE_ADDONS_PATH="${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons"
else
    OE_ADDONS_PATH="${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons"
fi

# Behind Nginx, Odoo must trust the X-Forwarded-* headers and only Nginx should reach it:
# bind the HTTP (OE_PORT) and gevent (GEVENT_PORT) ports to the loopback interface, so they are
# not reachable from the network. Otherwise anyone could bypass Nginx and, because of proxy_mode,
# forge their client IP with a X-Forwarded-For header. Both ports share this one setting.
# Without Nginx, Odoo has to listen on all interfaces to be reachable at all.
if [ "$INSTALL_NGINX" = "True" ]; then
    OE_PROXY_MODE="True"
    OE_HTTP_INTERFACE="127.0.0.1"
else
    OE_PROXY_MODE="False"
    OE_HTTP_INTERFACE="0.0.0.0"
fi

cat <<EOF | sudo tee /etc/${OE_CONFIG}.conf > /dev/null
[options]
; This is the password that allows database operations:
admin_passwd = ${OE_SUPERADMIN}
; Security: once your database(s) exist, set list_db = False to disable the
; unauthenticated database selector/manager (/web/database/*), which otherwise
; lets anyone enumerate database names. Left commented so the web database
; manager still works for creating the first database right after install.
; list_db = False
http_interface = ${OE_HTTP_INTERFACE}
http_port = ${OE_PORT}
gevent_port = ${GEVENT_PORT}
workers = ${WORKER_COUNT}
proxy_mode = ${OE_PROXY_MODE}
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
addons_path = ${OE_ADDONS_PATH}
EOF
sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

echo -e "* Create startup file"
cat <<EOF | sudo tee $OE_HOME_EXT/start.sh > /dev/null
#!/bin/sh
exec sudo -u $OE_USER $OE_VENV/bin/python $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf "\$@"
EOF
sudo chmod 755 $OE_HOME_EXT/start.sh

#--------------------------------------------------
# Adding ODOO as a deamon (systemd)
#--------------------------------------------------
echo -e "* Create systemd service file"
cat <<EOF | sudo tee /etc/systemd/system/${OE_CONFIG}.service > /dev/null
[Unit]
Description=Odoo
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=${OE_CONFIG}
PermissionsStartOnly=true
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_VENV/bin/python ${OE_HOME_EXT}/odoo-bin -c /etc/${OE_CONFIG}.conf
WorkingDirectory=${OE_HOME_EXT}
StandardOutput=journal+console
Restart=always

[Install]
WantedBy=multi-user.target
EOF

if has_systemd; then
  echo -e "* Reload systemd daemon"
  sudo systemctl daemon-reload

  echo -e "* Enable Odoo service to start on boot"
  sudo systemctl enable ${OE_CONFIG}.service
else
  echo "systemd is not running (container?): the service file is written but not enabled."
fi

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
if [ "$INSTALL_NGINX" = "True" ]; then
  echo -e "\n---- Installing and setting up Nginx ----"
  apt_get install nginx
  cat <<EOF | sudo tee /etc/nginx/sites-available/$WEBSITE_NAME > /dev/null
server {
  listen 80;

  # set proper server name after domain set
  server_name $WEBSITE_NAME;

  # Add Headers for odoo proxy mode
  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Real-IP \$remote_addr;
  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  proxy_set_header X-Client-IP \$remote_addr;
  proxy_set_header HTTP_X_FORWARDED_HOST \$remote_addr;

  #   odoo    log files
  access_log  /var/log/nginx/$OE_USER-access.log;
  error_log       /var/log/nginx/$OE_USER-error.log;

  #   increase    proxy   buffer  size
  proxy_buffers   16  64k;
  proxy_buffer_size   128k;

  proxy_read_timeout 900s;
  proxy_connect_timeout 900s;
  proxy_send_timeout 900s;

  #   force   timeouts    if  the backend dies
  proxy_next_upstream error   timeout invalid_header  http_500    http_502
  http_503;

  types {
    text/less less;
    text/scss scss;
  }

  #   enable  data    compression
  gzip    on;
  gzip_min_length 1100;
  gzip_buffers    4   32k;
  gzip_types  text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
  gzip_vary   on;
  client_header_buffer_size 4k;
  large_client_header_buffers 4 64k;
  client_max_body_size 0;

  location / {
    proxy_pass    http://127.0.0.1:$OE_PORT;
    # by default, do not forward anything
    proxy_redirect off;
  }

  # websocket (bus / discuss / live chat), served by the gevent worker
  location /websocket {
    proxy_pass http://127.0.0.1:$GEVENT_PORT;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  location ~* .(js|css|png|jpg|jpeg|gif|ico)$ {
    expires 2d;
    proxy_pass http://127.0.0.1:$OE_PORT;
    add_header Cache-Control "public, no-transform";
  }

  # cache some static data in memory for 60mins.
  location ~ /[a-zA-Z0-9_-]*/static/ {
    proxy_cache_valid 200 302 60m;
    proxy_cache_valid 404      1m;
    proxy_buffering    on;
    expires 864000;
    proxy_pass    http://127.0.0.1:$OE_PORT;
  }
}
EOF

  sudo ln -sf /etc/nginx/sites-available/$WEBSITE_NAME /etc/nginx/sites-enabled/$WEBSITE_NAME
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t
  if has_systemd; then
    sudo systemctl reload nginx
  fi
  echo "Done! The Nginx server is up and running. Configuration can be found at /etc/nginx/sites-available/$WEBSITE_NAME"
else
  echo "Nginx isn't installed due to choice of the user!"
fi

#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------

if [ "$INSTALL_NGINX" = "True" ] && [ "$ENABLE_SSL" = "True" ] && [ "$ADMIN_EMAIL" != "odoo@example.com" ]  && [ "$WEBSITE_NAME" != "_" ];then
  apt_get update
  apt_get install snapd
  sudo snap install core; sudo snap refresh core
  sudo snap install --classic certbot
  apt_get install python3-certbot-nginx
  sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  sudo systemctl reload nginx
  echo "SSL/HTTPS is enabled!"
else
  echo "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
  if [ "$ADMIN_EMAIL" = "odoo@example.com" ]; then
    echo "Certbot does not support registering odoo@example.com. You should use real e-mail address."
  fi
  if [ "$WEBSITE_NAME" = "_" ]; then
    echo "Website name is set as _. Cannot obtain SSL Certificate for _. You should use real website address."
  fi
fi

echo -e "* Starting Odoo Service"
if has_systemd; then
  sudo systemctl restart ${OE_CONFIG}.service
else
  echo "systemd is not running (container?): start Odoo manually with $OE_HOME_EXT/start.sh"
fi
echo "-----------------------------------------------------------"
echo "Done! The Odoo server is up and running. Specifications:"
echo "Port: $OE_PORT"
echo "Gevent (websocket) port: $GEVENT_PORT"
echo "Odoo listens on: $OE_HTTP_INTERFACE (127.0.0.1 = only reachable through Nginx)"
echo "User service: $OE_USER"
echo "Configuraton file location: /etc/${OE_CONFIG}.conf"
echo "Logfile location: /var/log/$OE_USER"
echo "Log rotation: daily, $LOG_RETENTION_DAYS days kept (/etc/logrotate.d/$OE_CONFIG)"
echo "User PostgreSQL: $OE_USER"
echo "Code location: $OE_HOME_EXT"
echo "Python virtualenv: $OE_VENV"
echo "Custom addons folder: $OE_HOME/custom/addons/"
echo "wkhtmltopdf: $(command -v wkhtmltopdf || echo 'NOT INSTALLED')"
echo "Password superadmin (database): $OE_SUPERADMIN"
echo "Start Odoo service: sudo systemctl start $OE_CONFIG"
echo "Stop Odoo service: sudo systemctl stop $OE_CONFIG"
echo "Restart Odoo service: sudo systemctl restart $OE_CONFIG"
if [ "$INSTALL_NGINX" = "True" ]; then
  echo "Nginx configuration file: /etc/nginx/sites-available/$WEBSITE_NAME"
fi
echo "-----------------------------------------------------------"
