#!/bin/bash
# -------------------------------
# STEP 1: Configuring the apache files
# -------------------------------

set +e 
setenforce 0
cp -rp /etc/httpd/conf.d /etc/httpd/conf.d-bkp

cat <<'FOREMANCONF' > /etc/httpd/conf.d/05-foreman.conf
<VirtualHost *:80>
  ServerName cent-07-01.vgs.com

  ## CORS Headers
  Header always set Access-Control-Allow-Origin "https://rocky-08-01.vgs.com:3000"
  Header always set Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE"
  Header always set Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization"
  Header always set Access-Control-Allow-Credentials "true"

  ## Vhost docroot
  DocumentRoot "/usr/share/foreman/public"

  <Directory "/usr/share/foreman/public">
    Options SymLinksIfOwnerMatch
    AllowOverride None
    Require all granted
  </Directory>

  IncludeOptional "/etc/httpd/conf.d/05-foreman.d/*.conf"

  ErrorLog "/var/log/httpd/foreman_error.log"
  ServerSignature Off
  CustomLog "/var/log/httpd/foreman_access.log" combined

  RequestHeader set X_FORWARDED_PROTO "http"
  RequestHeader set SSL_CLIENT_S_DN ""
  RequestHeader set SSL_CLIENT_CERT ""
  RequestHeader set SSL_CLIENT_VERIFY ""
  RequestHeader unset REMOTE-USER
  RequestHeader unset REMOTE_USER
  RequestHeader unset REMOTE-USER-EMAIL
  RequestHeader unset REMOTE_USER_EMAIL
  RequestHeader unset REMOTE-USER-FIRSTNAME
  RequestHeader unset REMOTE_USER_FIRSTNAME
  RequestHeader unset REMOTE-USER-LASTNAME
  RequestHeader unset REMOTE_USER_LASTNAME
  RequestHeader unset REMOTE-USER-GROUPS
  RequestHeader unset REMOTE_USER_GROUPS

  <Location "/pulp/deb">
    RequestHeader unset X-CLIENT-CERT
    RequestHeader set X-CLIENT-CERT "%{SSL_CLIENT_CERT}s" env=SSL_CLIENT_CERT
    ProxyPass unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content disablereuse=on timeout=600
    ProxyPassReverse unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content
  </Location>

  <Location "/pulp/isos">
    RequestHeader unset X-CLIENT-CERT
    RequestHeader set X-CLIENT-CERT "%{SSL_CLIENT_CERT}s" env=SSL_CLIENT_CERT
    ProxyPass unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content disablereuse=on timeout=600
    ProxyPassReverse unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content
  </Location>

  <Location "/pulp/repos">
    RequestHeader unset X-CLIENT-CERT
    RequestHeader set X-CLIENT-CERT "%{SSL_CLIENT_CERT}s" env=SSL_CLIENT_CERT
    ProxyPass unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content disablereuse=on timeout=600
    ProxyPassReverse unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content
  </Location>

  Alias /pub /var/www/html/pub

  <Location /pub>
    <IfModule mod_passenger.c>
      PassengerEnabled off
    </IfModule>
    Options +FollowSymLinks +Indexes
    Require all granted
  </Location>

  <Location "/pulp/content">
    RequestHeader unset X-CLIENT-CERT
    RequestHeader set X-CLIENT-CERT "%{SSL_CLIENT_CERT}s" env=SSL_CLIENT_CERT
    ProxyPass unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content disablereuse=on timeout=600
    ProxyPassReverse unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content
  </Location>

  ProxyRequests Off
  ProxyPreserveHost On
  ProxyAddHeaders On
  ProxyPass /pulp !
  ProxyPass /pub !
  ProxyPass /icons !
  ProxyPass /images !
  ProxyPass /server-status !
  ProxyPass /webpack !
  ProxyPass /assets !
  ProxyPass / unix:///run/foreman.sock|http://foreman/ retry=0 timeout=900
  ProxyPassReverse / unix:///run/foreman.sock|http://foreman/

  RewriteEngine On
  RewriteCond %{HTTP:Upgrade} =websocket [NC]
  RewriteRule /(.*) unix:///run/foreman.sock|ws://foreman/$1 [P,L]

  ServerAlias foreman

  <FilesMatch \.css\.gz$>
    ForceType text/css
    Header set Content-Encoding gzip
    SetEnv no-gzip
  </FilesMatch>
  <FilesMatch \.js\.gz$>
    ForceType text/javascript
    Header set Content-Encoding gzip
    SetEnv no-gzip
  </FilesMatch>
  <FilesMatch \.svg\.gz$>
    ForceType image/svg+xml
    Header set Content-Encoding gzip
    SetEnv no-gzip
  </FilesMatch>

  <LocationMatch "^/(assets|webpack)">
    Options SymLinksIfOwnerMatch
    AllowOverride None
    Require all granted

    <IfModule mod_expires.c>
      Header unset ETag
      FileETag None
      ExpiresActive On
      ExpiresDefault "access plus 1 year"
    </IfModule>

    RewriteEngine On
    RewriteCond %{HTTP:Accept-Encoding} \b(x-)?gzip\b
    RewriteCond %{REQUEST_FILENAME} \.(css|js|svg)$
    RewriteCond %{REQUEST_FILENAME}.gz -s
    RewriteRule ^(.+) $1.gz [L]
  </LocationMatch>

  AddDefaultCharset UTF-8
</VirtualHost>
FOREMANCONF

cat <<'FOREMANSSL' > /etc/httpd/conf.d/05-foreman-ssl.conf
# ************************************
# Vhost template in module puppetlabs-apache
# Managed by Puppet
# ************************************
# 
<VirtualHost *:443>
  ServerName cent-07-01.vgs.com

  ## Vhost docroot
  DocumentRoot "/usr/share/foreman/public"

  ## Directories, there should at least be a declaration for /usr/share/foreman/public
  Header always set Access-Control-Allow-Origin "https://rocky-08-01.vgs.com:3000"
  Header always set Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE"
  Header always set Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization"
  Header always set Access-Control-Allow-Credentials "true"

  <Location "/users/login">
    Header always set Access-Control-Allow-Origin "https://rocky-08-01.vgs.com:3000"
    Header always set Access-Control-Allow-Credentials "true"
  </Location>

  <Directory "/usr/share/foreman/public">
    Options SymLinksIfOwnerMatch
    AllowOverride None
    Require all granted
  </Directory>

  ## Load additional static includes
  IncludeOptional "/etc/httpd/conf.d/05-foreman-ssl.d/*.conf"

  ## Logging
  ErrorLog "/var/log/httpd/foreman-ssl_error_ssl.log"
  ServerSignature Off
  CustomLog "/var/log/httpd/foreman-ssl_access_ssl.log" combined 

  ## Request header rules
  ## as per http://httpd.apache.org/docs/2.4/mod/mod_headers.html#requestheader
  RequestHeader set X_FORWARDED_PROTO "https"
  RequestHeader set SSL_CLIENT_S_DN "%{SSL_CLIENT_S_DN}s"
  RequestHeader set SSL_CLIENT_CERT "%{SSL_CLIENT_CERT}s"
  RequestHeader set SSL_CLIENT_VERIFY "%{SSL_CLIENT_VERIFY}s"
  RequestHeader unset REMOTE-USER
  RequestHeader unset REMOTE_USER
  RequestHeader unset REMOTE-USER-EMAIL
  RequestHeader unset REMOTE-USER_EMAIL
  RequestHeader unset REMOTE_USER-EMAIL
  RequestHeader unset REMOTE_USER_EMAIL
  RequestHeader unset REMOTE-USER-FIRSTNAME
  RequestHeader unset REMOTE-USER_FIRSTNAME
  RequestHeader unset REMOTE_USER-FIRSTNAME
  RequestHeader unset REMOTE_USER_FIRSTNAME
  RequestHeader unset REMOTE-USER-LASTNAME
  RequestHeader unset REMOTE-USER_LASTNAME
  RequestHeader unset REMOTE_USER-LASTNAME
  RequestHeader unset REMOTE_USER_LASTNAME
  RequestHeader unset REMOTE-USER-GROUPS
  RequestHeader unset REMOTE-USER_GROUPS
  RequestHeader unset REMOTE_USER-GROUPS
  RequestHeader unset REMOTE_USER_GROUPS

  # SSL Proxy directives
  SSLProxyEngine On

  ProxyPass /pulp_ansible/galaxy/ unix:///run/pulpcore-api.sock|http://pulpcore-api/pulp_ansible/galaxy/
  ProxyPassReverse /pulp_ansible/galaxy/ unix:///run/pulpcore-api.sock|http://pulpcore-api/pulp_ansible/galaxy/

  <Location "/pulpcore_registry/v2/">
    RequestHeader unset REMOTE-USER
    RequestHeader unset REMOTE_USER
    RequestHeader set REMOTE-USER "admin" "expr=%{SSL_CLIENT_S_DN_CN} == 'cent-07-01.vgs.com'"
    ProxyPass unix:///run/pulpcore-api.sock|http://pulpcore-api/v2/
    ProxyPassReverse unix:///run/pulpcore-api.sock|http://pulpcore-api/v2/
  </Location>

  ProxyPass /pulp/container/ unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/container/
  ProxyPassReverse /pulp/container/ unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/container/

  <Location "/pulp/deb">
    RequestHeader unset X-CLIENT-CERT
    RequestHeader set X-CLIENT-CERT "%{SSL_CLIENT_CERT}s" env=SSL_CLIENT_CERT
    ProxyPass unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content disablereuse=on timeout=600
    ProxyPassReverse unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content
  </Location>

  <Location "/pulp/isos">
    RequestHeader unset X-CLIENT-CERT
    RequestHeader set X-CLIENT-CERT "%{SSL_CLIENT_CERT}s" env=SSL_CLIENT_CERT
    ProxyPass unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content disablereuse=on timeout=600
    ProxyPassReverse unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content
  </Location>

  <Location "/pulp/repos">
    RequestHeader unset X-CLIENT-CERT
    RequestHeader set X-CLIENT-CERT "%{SSL_CLIENT_CERT}s" env=SSL_CLIENT_CERT
    ProxyPass unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content disablereuse=on timeout=600
    ProxyPassReverse unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content
  </Location>
Alias /pub /var/www/html/pub

<Location /pub>
  <IfModule mod_passenger.c>
    PassengerEnabled off
  </IfModule>
  Options +FollowSymLinks +Indexes
  Require all granted
</Location>

  <Location "/pulp/content">
    RequestHeader unset X-CLIENT-CERT
    RequestHeader set X-CLIENT-CERT "%{SSL_CLIENT_CERT}s" env=SSL_CLIENT_CERT
    ProxyPass unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content disablereuse=on timeout=600
    ProxyPassReverse unix:///run/pulpcore-content.sock|http://pulpcore-content/pulp/content
  </Location>

  <Location "/pulp/api/v3">
    RequestHeader unset REMOTE-USER
    RequestHeader unset REMOTE_USER
    RequestHeader set REMOTE-USER "%{SSL_CLIENT_S_DN_CN}s" env=SSL_CLIENT_S_DN_CN
    RequestHeader set REMOTE-USER "admin" "expr=%{SSL_CLIENT_S_DN_CN} == 'cent-07-01.vgs.com'"
    ProxyPass unix:///run/pulpcore-api.sock|http://pulpcore-api/pulp/api/v3 timeout=600
    ProxyPassReverse unix:///run/pulpcore-api.sock|http://pulpcore-api/pulp/api/v3
  </Location>

  ProxyPass /pulp/assets/ unix:///run/pulpcore-api.sock|http://pulpcore-api/pulp/assets/
  ProxyPassReverse /pulp/assets/ unix:///run/pulpcore-api.sock|http://pulpcore-api/pulp/assets/

  ## Proxy rules
  ProxyRequests Off
  ProxyPreserveHost On
  ProxyAddHeaders On
  ProxyPass /pulp !
  ProxyPass /pub !
  ProxyPass /icons !
  ProxyPass /images !
  ProxyPass /server-status !
  ProxyPass /webpack !
  ProxyPass /assets !
  ProxyPass / unix:///run/foreman.sock|http://foreman/ retry=0 timeout=900
  ProxyPassReverse / unix:///run/foreman.sock|http://foreman/
  ## Rewrite rules
  RewriteEngine On

  #Upgrade Websocket connections
  RewriteCond %{HTTP:Upgrade} =websocket [NC]
  RewriteRule /(.*) unix:///run/foreman.sock|ws://foreman/$1 [P,L]


  ## Server aliases
  ServerAlias foreman

  ## SSL directives
  SSLEngine on
  SSLCertificateFile      "/etc/pki/katello/certs/katello-apache.crt"
  SSLCertificateKeyFile   "/etc/pki/katello/private/katello-apache.key"
  SSLCertificateChainFile "/etc/pki/katello/certs/katello-server-ca.crt"
  SSLVerifyClient         optional
  SSLVerifyDepth          3
  SSLCACertificateFile    "/etc/pki/katello/certs/katello-default-ca.crt"
  SSLOptions +StdEnvVars +ExportCertData

  ## Custom fragment
  # Set headers for all possible assets which are compressed
<FilesMatch \.css\.gz$>
  ForceType text/css
  Header set Content-Encoding gzip
  SetEnv no-gzip
</FilesMatch>
<FilesMatch \.js\.gz$>
  ForceType text/javascript
  Header set Content-Encoding gzip
  SetEnv no-gzip
</FilesMatch>
<FilesMatch \.svg\.gz$>
  ForceType image/svg+xml
  Header set Content-Encoding gzip
  SetEnv no-gzip
</FilesMatch>

<LocationMatch "^/(assets|webpack)">
  Options SymLinksIfOwnerMatch
  AllowOverride None
  Require all granted

  # Use standard http expire header for assets instead of ETag
  <IfModule mod_expires.c>
    Header unset ETag
    FileETag None
    ExpiresActive On
    ExpiresDefault "access plus 1 year"
  </IfModule>

  # Return compressed assets if they are precompiled
  RewriteEngine On
  # Make sure the browser supports gzip encoding and file with .gz added
  # does exist on disc before we rewrite with the extension
  RewriteCond %{HTTP:Accept-Encoding} \b(x-)?gzip\b
  RewriteCond %{REQUEST_FILENAME} \.(css|js|svg)$
  RewriteCond %{REQUEST_FILENAME}.gz -s
  RewriteRule ^(.+) $1.gz [L]
</LocationMatch>

# Handle CORS preflight OPTIONS requests
  <IfModule mod_headers.c>
    Header always set Access-Control-Allow-Origin "https://rocky-08-01.vgs.com:3000"
    Header always set Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE"
    Header always set Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization"
    Header always set Access-Control-Allow-Credentials "true"
  </IfModule>

# Respond to OPTIONS requests with 200 OK
  RewriteEngine On
  RewriteCond %{REQUEST_METHOD} OPTIONS
  RewriteRule ^(.*)$ $1 [R=200,L]


  AddDefaultCharset UTF-8
</VirtualHost>
FOREMANSSL

# -------------------------------
# STEP 2: Generate Remote Installer Script
# -------------------------------
cat <<'EOF' > /tmp/foreman_frontend.sh
#!/bin/bash
set -e
dnf module reset nodejs -y
sudo dnf module enable -y nodejs:18
sudo dnf install -y nodejs npm
npx create-react-app foreman-frontend -y
mkdir -p /root/foreman-frontend/ssl
openssl req -x509 -newkey rsa:2048 -nodes -keyout /root/foreman-frontend/ssl/server.key -out /root/foreman-frontend/ssl/server.crt -days 365 -subj "/O=VGS/OU=VGS/CN=rocky-08-01.vgs.com"

npm install react-app-rewired -y
npm install react-router-dom -y
npm install axios -y

cat <<'CONFIGJS' > /root/foreman-frontend/config-overrides.js
const fs = require('fs');

module.exports = function override(config, env) {
  config.devServer = {
    ...config.devServer,
    https: {
      key: fs.readFileSync('/root/foreman-frontend/ssl/server.key'),
      cert: fs.readFileSync('/root/foreman-frontend/ssl/server.crt')
    },
    disableHostCheck: true
  };
  return config;
};
CONFIGJS

cat <<'PACKAGEJS' > /root/foreman-frontend/package.json
{
  "name": "foreman-frontend",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "@testing-library/dom": "^10.4.1",
    "@testing-library/jest-dom": "^6.7.0",
    "@testing-library/react": "^16.3.0",
    "@testing-library/user-event": "^13.5.0",
    "axios": "^1.11.0",
    "http-proxy-middleware": "^3.0.5",
    "https-browserify": "^1.0.0",
    "react": "^19.1.1",
    "react-dom": "^19.1.1",
    "react-router-dom": "^6.30.1",
    "web-vitals": "^2.1.4"
  },
  "scripts": {
    "start": "react-app-rewired start",
    "build": "react-app-rewired build",
    "test": "react-app-rewired test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "resolutions": {
    "nth-check": "^2.0.1",
    "postcss": "^8.4.31",
    "webpack-dev-server": "^4.15.1"
  },
  "devDependencies": {
    "react-app-rewired": "^2.2.1",
    "react-scripts": "^5.0.1"
  }
}
PACKAGEJS

cat <<'ENVFILE' > /root/foreman-frontend/.env
REACT_APP_API_URL=https://cent-07-01.vgs.com/api/v2
REACT_APP_API_USER=admin
REACT_APP_API_PASS=zqs977dXzqfEvTML
HTTPS=true
SSL_CRT_FILE=/root/foreman-frontend/ssl/server.crt
SSL_KEY_FILE=/root/foreman-frontend/ssl/server.key
ENVFILE

cat <<'APIJS' > /root/foreman-frontend/src/api.js
import axios from "axios";

const API = axios.create({
  baseURL: process.env.REACT_APP_API_URL || "https://cent-07-01.vgs.com/api/v2",
  auth: {
    username: process.env.REACT_APP_API_USER,
    password: process.env.REACT_APP_API_PASS
  },
  withCredentials: false,
  headers: {
    "Content-Type": "application/json"
  }
});

export function listMedia() {
  return API.get("/media");
}

export default API;
APIJS

cat <<'APPCSS' > /root/foreman-frontend/src/App.css
body {
  margin: 0;
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
  background: linear-gradient(to right, #f0f4f8, #d9e2ec);
  color: #333;
}

.container {
  max-width: 900px;
  margin: 40px auto;
  padding: 30px;
  background-color: white;
  border-radius: 12px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

h1, h2 {
  text-align: center;
  color: #2c3e50;
}

form > div {
  margin-bottom: 15px;
}

input, select {
  width: 100%;
  padding: 8px;
  margin-top: 4px;
  border: 1px solid #ccc;
  border-radius: 6px;
  box-sizing: border-box;
}

button {
  padding: 10px 20px;
  background-color: #3498db;
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  transition: background-color 0.3s ease;
}

button:hover {
  background-color: #2980b9;
}

table {
  margin-top: 30px;
  width: 100%;
  border-collapse: collapse;
}

th {
  background-color: #3498db;
  color: white;
  padding: 10px;
  text-align: left;
}

td {
  background-color: #ecf0f1;
  padding: 10px;
  text-align: center;
}

.delete-button {
  background-color: #d9534f;
  color: white;
  border: none;
  padding: 8px 12px;
  border-radius: 6px;
  cursor: pointer;
  transition: background-color 0.3s ease;
}

.delete-button:hover {
  background-color: #c9302c;
}
APPCSS

cat <<'SETUPJS' > /root/foreman-frontend/src/setupProxy.js
const { createProxyMiddleware } = require('http-proxy-middleware');

module.exports = function (app) {
  app.use(
    '/api/v2',
    createProxyMiddleware({
      target: 'https://cent-07-01.vgs.com',
      changeOrigin: true,
      secure: false
    })
  );
};
SETUPJS

# App.js
echo "Creating App.js..."
cat <<'APPJS' > /root/foreman-frontend/src/App.js
import React, { useState, useEffect } from "react";
import api from "./api";
import "./App.css";

function App() {
  const [formData, setFormData] = useState({
    name: "",
    location_id: "",
    organization_id: "",
    architecture_id: "",
    domain_id: "",
    operatingsystem_id: "",
    hostgroup_id: "",
    ptable_id: "",
    medium_id: "",
    subnet_id: "",
    root_pass: "",
    ip: "",
    mac: "",
    forceBuild: false,
  });

  const [dropdowns, setDropdowns] = useState({
    locations: [],
    organizations: [],
    architectures: [],
    domains: [],
    operatingSystems: [],
    hostgroups: [],
    ptables: [],
    media: [],
    subnets: [],
  });

  const [hosts, setHosts] = useState([]);
  const [message, setMessage] = useState({ type: "", text: "" });
  const [loading, setLoading] = useState(true);

  // Fetch dropdown data
  useEffect(() => {
    const fetchDropdowns = async () => {
      try {
        const endpoints = [
          "locations",
          "organizations",
          "architectures",
          "domains",
          "operatingsystems",
          "hostgroups",
          "ptables",
          "media",
          "subnets",
        ];

        const results = await Promise.all(
          endpoints.map((ep) => api.get(`/${ep}?per_page=100`))
        );

        const data = {};
        endpoints.forEach((key, i) => {
          data[key] = results[i].data.results || results[i].data;
        });

        setDropdowns({
          locations: data.locations,
          organizations: data.organizations,
          architectures: data.architectures,
          domains: data.domains,
          operatingSystems: data.operatingsystems,
          hostgroups: data.hostgroups,
          ptables: data.ptables,
          media: data.media,
          subnets: data.subnets,
        });

        setLoading(false);
      } catch (err) {
        setMessage({ type: "error", text: "Failed to load dropdowns." });
        setLoading(false);
      }
    };

    fetchDropdowns();
  }, []);

  // Fetch hosts
  useEffect(() => {
    const fetchHosts = async () => {
      try {
        const res = await api.get("/hosts?per_page=100");
        setHosts(res.data.results || []);
      } catch (err) {
        console.error("Error fetching hosts:", err);
      }
    };
    fetchHosts();
  }, [message]);

  const handleChange = (key, value) => {
    setFormData({ ...formData, [key]: value });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setMessage({ type: "", text: "" });

    try {
      const payload = {
        host: {
          ...formData,
          managed: true,
          build: formData.forceBuild,
        },
      };

      Object.keys(payload.host).forEach((key) => {
        if (payload.host[key] === "") delete payload.host[key];
      });

      await api.post("/hosts", payload);
      setMessage({ type: "success", text: "Host created successfully!" });
      setFormData({
        name: "",
        location_id: "",
        organization_id: "",
        architecture_id: "",
        domain_id: "",
        operatingsystem_id: "",
        hostgroup_id: "",
        ptable_id: "",
        medium_id: "",
        subnet_id: "",
        root_pass: "",
        ip: "",
        mac: "",
        forceBuild: false,
      });
    } catch (err) {
      const msg = err.response?.data?.error?.message || err.message;
      setMessage({ type: "error", text: `Error creating host: ${msg}` });
    }
  };

  const handleDelete = async (id, name) => {
    if (!window.confirm(`Delete host "${name}"?`)) return;
    try {
      await api.delete(`/hosts/${id}`);
      setMessage({ type: "success", text: `Host "${name}" deleted.` });
    } catch (err) {
      const msg = err.response?.data?.error?.message || err.message;
      setMessage({ type: "error", text: `Failed to delete host: ${msg}` });
    }
  };

  const renderDropdown = (label, key, options, required = true) => (
    <div>
      <label>{label}</label>
      <select
        value={formData[key]}
        onChange={(e) => handleChange(key, e.target.value)}
        required={required}
      >
        <option value="">Select {label}</option>
        {options.map((opt) => (
          <option key={opt.id} value={opt.id}>
            {opt.name}
          </option>
        ))}
      </select>
    </div>
  );

  if (loading) return <div>Loading dropdowns...</div>;

  return (
    <div className="container">
      <h1>Create Host in Foreman</h1>
      {message.text && (
        <div style={{ color: message.type === "error" ? "red" : "green" }}>
          {message.text}
        </div>
      )}

      <form onSubmit={handleSubmit}>
        <div>
          <label>Host Name</label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => handleChange("name", e.target.value)}
            required
          />
        </div>

        {renderDropdown("Location", "location_id", dropdowns.locations)}
        {renderDropdown("Organization", "organization_id", dropdowns.organizations)}
        {renderDropdown("Architecture", "architecture_id", dropdowns.architectures)}
        {renderDropdown("Domain", "domain_id", dropdowns.domains)}
        {renderDropdown("Operating System", "operatingsystem_id", dropdowns.operatingSystems)}
        {renderDropdown("Partition Table", "ptable_id", dropdowns.ptables)}
        {renderDropdown("Installation Medium", "medium_id", dropdowns.media)}
        {renderDropdown("Subnet", "subnet_id", dropdowns.subnets)}
        {renderDropdown("Host Group (Optional)", "hostgroup_id", dropdowns.hostgroups, false)}

        <div>
          <label>IP Address</label>
          <input
            type="text"
            value={formData.ip}
            onChange={(e) => handleChange("ip", e.target.value)}
            required
          />
        </div>

        <div>
          <label>MAC Address</label>
          <input
            type="text"
            value={formData.mac}
            onChange={(e) => handleChange("mac", e.target.value.toUpperCase())}
            required
          />
        </div>

        <div>
          <label>Root Password</label>
          <input
            type="password"
            value={formData.root_pass}
            onChange={(e) => handleChange("root_pass", e.target.value)}
            required
          />
        </div>

        <div>
          <label>
            <input
              type="checkbox"
              checked={formData.forceBuild}
              onChange={(e) => handleChange("forceBuild", e.target.checked)}
            />
            Force Build
          </label>
        </div>

        <button type="submit">Create Host</button>
      </form>

      <hr />
      <h2>All Hosts</h2>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>OS</th>
            <th>IP</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {hosts.map((host) => (
            <tr key={host.id}>
              <td>{host.name}</td>
              <td>{host.operatingsystem_name}</td>
              <td>{host.ip}</td>
              <td>{host.build ? "Building" : "Ready"}</td>
              <td>
                <button onClick={() => handleDelete(host.id, host.name)}>Delete</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default App;
APPJS

mkdir -p /root/foreman-frontend/src/components/

cat <<'TABLEJS' > /root/foreman-frontend/src/components/HostsTable.js
import React, { useEffect, useState } from 'react';
import api from '../api'; // adjust path if needed

const HostsTable = ({ onEdit }) => {
  const [hosts, setHosts] = useState([]);
  const [error, setError] = useState('');

  useEffect(() => {
    const fetchHosts = async () => {
      try {
        const response = await api.get('/hosts');
        console.log('Fetched hosts:', response.data);
        setHosts(response.data.results || []);
      } catch (err) {
        console.error('Error fetching hosts:', err);
        setError('Failed to fetch hosts');
      }
    };

    fetchHosts();
  }, []);

  return (
    <div>
      <h2>All Hosts</h2>
      {error && <p style={{ color: 'red' }}>{error}</p>}
      <table border="1" cellPadding="8" style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr>
            <th>Name</th>
            <th>OS</th>
            <th>IP</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {hosts.length > 0 ? (
            hosts.map((host) => (
              <tr key={host.id}>
                <td>{host.name}</td>
                <td>{host.operatingsystem_name || '—'}</td>
                <td>{host.ip || '—'}</td>
                <td>{host.build ? 'Building' : 'Ready'}</td>
                <td>
                  <button onClick={() => onEdit(host)}>Edit</button>
                </td>
              </tr>
            ))
          ) : (
            <tr>
              <td colSpan="4" style={{ textAlign: 'center' }}>No hosts found</td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
};

export default HostsTable;
TABLEJS


echo "=== Installing Nginx ==="
dnf install nginx -y

echo "=== Enabling and starting Nginx ==="
systemctl enable nginx
systemctl start nginx

echo "=== Creating SSL directory ==="
mkdir -p /etc/nginx/ssl

echo "=== Copying SSL certificates ==="
cp /root/foreman-frontend/ssl/server.crt /etc/nginx/ssl/rocky.crt
cp /root/foreman-frontend/ssl/server.key /etc/nginx/ssl/rocky.key

echo "=== Writing Nginx config: /etc/nginx/conf.d/foreman-api.conf ==="
cat << 'EOF' > /etc/nginx/conf.d/foreman-api.conf
# Redirect port 3000 → 443
server {
    listen 3000 ssl;
    server_name rocky-08-01.vgs.com;

    ssl_certificate     /etc/nginx/ssl/rocky.crt;
    ssl_certificate_key /etc/nginx/ssl/rocky.key;

    return 301 https://rocky-08-01.vgs.com$request_uri;
}

# Main server block on HTTPS (443)
server {
    listen 443 ssl;
    server_name rocky-08-01.vgs.com;

    ssl_certificate     /etc/nginx/ssl/rocky.crt;
    ssl_certificate_key /etc/nginx/ssl/rocky.key;

    # -------------------------------
    # ✅ Foreman API Reverse Proxy
    # -------------------------------
    location /api/ {
        proxy_pass https://cent-07-01.vgs.com/api/;

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;

        proxy_ssl_verify off;
    }

    # -------------------------------
    # ✅ React Frontend UI
    # -------------------------------
    root /var/www/foreman-frontend;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

echo "=== Testing Nginx configuration ==="
nginx -t

echo "=== Restarting Nginx ==="
systemctl restart nginx
systemctl status nginx --no-pager

echo "=== Building Foreman frontend ==="
cd /root/foreman-frontend/
npm install
npm run build

echo "=== Deploying frontend to /var/www/foreman-frontend ==="
mkdir -p /var/www/foreman-frontend
cp -r /root/foreman-frontend/build/* /var/www/foreman-frontend/

echo "=== Setting permissions ==="
chown -R nginx:nginx /var/www/foreman-frontend
chmod -R 755 /var/www/foreman-frontend

echo "=== Final Nginx reload ==="
nginx -t
systemctl restart nginx
systemctl status nginx --no-pager

firewall-cmd --add-port=3000/tcp --permanent
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --reload

systemctl daemon-reexec

npm install axios

echo "All copied."
EOF

# -------------------------------
# STEP 3: Transfer Remote Script
# -------------------------------
echo "🚀 Transferring script..."
sshpass -p 'Root@123' scp -o StrictHostKeyChecking=no /tmp/foreman_frontend.sh root@rocky-08-01.vgs.com:/root/

# -------------------------------
# STEP 4: Execute Remote Script
# -------------------------------
echo "🚀 Executing remote script..."
sshpass -p 'Root@123' ssh -o StrictHostKeyChecking=no root@rocky-08-01.vgs.com "bash /root/foreman_frontend.sh"

systemctl restart httpd
