Markdown
# VGS Lab DNS Appliance (DNSManager)

An enterprise-grade, split-horizon local DNS appliance desktop management console built using **Go**, **Wails (Vite + React)**, and a pure-Go implementation of **SQLite**.

This application functions as a dedicated local infrastructure gateway for private homelabs. It allows systems administrators to dynamically provision, modify, and purge localized core infrastructure network records (`A`, `AAAA`, `CNAME`, `PTR`) for hypervisors (VMware ESXi, vCenter instances) and enterprise Linux server clusters (Rocky Linux, CentOS) via an embedded modern UI dashboard. Concurrently, the engine seamlessly proxies all non-local public requests to upstream internet DNS authorities over optimized socket connections.

Because we are utilizing `modernc.org/sqlite`, **CGO is entirely disabled**. This eliminates any requirement for a local C-compiler (MSYS2/GCC) on Windows, providing a fast, native, and friction-free compilation workflow using your manually installed environment components.

---

## 🏗️ Core Architecture & Split-Horizon Logic

The appliance utilizes a single-binary architecture with an isolated backend service loop and an embedded data persistence layer, eliminating the need for a separate database or engine process.

### 1. Database Schema (`database/sqlite.go`)
Data persistence is handled by a local `records.db` file driven by a pure-Go SQLite driver (`modernc.org/sqlite`). This driver works entirely in user space, sidestepping Windows CGO/C-compiler toolchain requirements.

```sql
CREATE TABLE IF NOT EXISTS records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hostname TEXT NOT NULL,
    ip TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'A',
    ttl INTEGER DEFAULT 60
);
2. Resolution Processing Pipeline (dns/dns.go)
The application binds to port 53/UDP on all interfaces (0.0.0.0:53) and handles incoming queries via the following logic flow:

Inbound Query Evaluation: The packet is unpacked and parsed for the target domain string and query type (A, AAAA, CNAME, PTR).

Local Lookup Phase: The engine searches the SQLite database. If a matching hostname and record type exist, it constructs a success answer payload (RcodeSuccess) with the configured translation target and returns it to the client immediately.

Zone Boundary Filtering: If the record is missing from the database but contains a target hostname ending in .vgs or vgs.com, the engine intercepts it as an internal zone boundary failure and drops an authoritative NXDOMAIN (RcodeNameError) response to prevent leakage to public authorities.

Upstream Proxy Phase: If the query is outside the internal laboratory domain boundaries, the request is transparently proxied over UDP to public upstream recursive servers (1.1.1.1:53) with a strict 2-second timeout threshold before returning the answer to the workstation client.

📂 Project Directory Structure
Plaintext
C:\Projects\DNSManager\
├── database/          
│   └── sqlite.go      <-- Custom Pure-Go Data Logic Layer (SQLite initialization)
├── dns/               
│   └── dns.go         <-- Custom DNS Socket Processing Layer (Port 53 Engine)
├── frontend/          
│   ├── src/
│   │   └── App.jsx    <-- Desktop UI Dashboard Component (React/Vite)
│   └── package.json   
├── app.go             <-- Wails Application Bindings & Startup Routines
├── main.go            <-- Main Entrypoint & Window Configuration Setup
├── go.mod             <-- Go Module Dependencies
├── wails.json         <-- Wails Framework Environment Declarations
└── README.md          <-- Systems Architecture & Lifecycle Guide
🛠️ Environment Path Alignment & Core Workspace Initialization
Execute these terminal commands sequentially inside an elevated PowerShell window (Run as Administrator). Since you have already manually downloaded and installed Node.js v24.16.0-x64 and Go 1.25.11 from the web, this phase maps your workspace binary paths and pulls down the Wails CLI framework tool.

PowerShell
# 1. Map your manual Go user binary space to the active and permanent environment variables
$env:Path += ";$env:USERPROFILE\go\bin"
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$env:USERPROFILE\go\bin", "User")

# 2. Construct the project subdirectory matrix layout
New-Item -ItemType Directory -Path "C:\Projects\DNSManager"
New-Item -ItemType Directory -Path "C:\Projects\DNSManager\database"
New-Item -ItemType Directory -Path "C:\Projects\DNSManager\dns"

# 3. Pull down, compile, and deploy the global Wails framework command line application binaries
go install [github.com/wailsapp/wails/v2/cmd/wails@latest](https://github.com/wailsapp/wails/v2/cmd/wails@latest)

# 4. Verify system installation versions match project constraints
go version
node -v
npm -v
wails doctor
💻 Code Catalog Map
Deploy the files below into your configured workspace folders:

## ##FILE: C:\Projects\DNSManager\wails.json
JSON
{
  "$schema": "[https://wails.io/schemas/config.v2.json](https://wails.io/schemas/config.v2.json)",
  "name": "DNSManager",
  "outputfilename": "DNSManager",
  "frontend:dir": "frontend",
  "wailsjs:dir": "frontend/wailsjs",
  "author": {
    "name": "VGS Systems Administrator",
    "email": "sysadmin@vgs.com"
  }
}
##FILE: C:\Projects\DNSManager\go.mod
Go
module DNSManager

go 1.25.11

require (
	[github.com/miekg/dns](https://github.com/miekg/dns) v1.1.58
	[github.com/wailsapp/wails/v2](https://github.com/wailsapp/wails/v2) v2.9.2
	modernc.org/sqlite v1.34.5
)
##FILE: C:\Projects\DNSManager\main.go
Go
package main

import (
	"embed"

	"[github.com/wailsapp/wails/v2](https://github.com/wailsapp/wails/v2)"
	"[github.com/wailsapp/wails/v2/pkg/options](https://github.com/wailsapp/wails/v2/pkg/options)"
	"[github.com/wailsapp/wails/v2/pkg/options/assetserver](https://github.com/wailsapp/wails/v2/pkg/options/assetserver)"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	app := NewApp()

	err := wails.Run(&options.App{
		Title:  "DNS Manager - VGS Appliance",
		Width:  1024,
		Height: 768,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 27, G: 38, B: 56, A: 1},
		OnStartup:        app.startup,
		Bind: []interface{}{
			app,
		},
	})

	if err != nil {
		println("Error:", err.Error())
	}
}
##FILE: C:\Projects\DNSManager\app.go
Go
package main

import (
	"context"
	"fmt"

	"DNSManager/database"
	"DNSManager/dns"
)

type App struct {
	ctx context.Context
}

func NewApp() *App {
	return &App{}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx

	if err := database.Init(); err != nil {
		println("Database Error:", err.Error())
	} else {
		println("SQLite initialized successfully")
	}

	if err := dns.Start(); err != nil {
		println("DNS Error:", err.Error())
	}
}

func (a *App) Greet(name string) string {
	return fmt.Sprintf("Hello %s, It's show time!", name)
}

func (a *App) GetRecords() ([]database.Record, error) {
	return database.GetRecords()
}

func (a *App) AddRecord(hostname string, ip string, recordType string) error {
	return database.AddRecord(hostname, ip, recordType)
}

func (a *App) DeleteRecord(id int) error {
	return database.DeleteRecord(id)
}
##FILE: C:\Projects\DNSManager\database\sqlite.go
Go
package database

import (
	"database/sql"

	_ "modernc.org/sqlite"
)

var DB *sql.DB

type Record struct {
	ID       int    `json:"id"`
	Hostname string `json:"hostname"`
	IP       string `json:"ip"`
	Type     string `json:"type"`
	TTL      int    `json:"ttl"`
}

func Init() error {
	var err error

	DB, err = sql.Open("sqlite", "records.db")
	if err != nil {
		return err
	}

	_, err = DB.Exec(`
	CREATE TABLE IF NOT EXISTS records (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		hostname TEXT NOT NULL,
		ip TEXT NOT NULL,
		type TEXT NOT NULL DEFAULT 'A',
		ttl INTEGER DEFAULT 60
	)`)

	return err
}

func AddRecord(hostname string, ip string, recordType string) error {
	if recordType == "" {
		recordType = "A"
	}
	_, err := DB.Exec(
		"INSERT INTO records(hostname, ip, type, ttl) VALUES (?, ?, ?, ?)",
		hostname,
		ip,
		recordType,
		60,
	)
	return err
}

func GetRecords() ([]Record, error) {
	rows, err := DB.Query("SELECT id, hostname, ip, type, ttl FROM records ORDER BY hostname")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var records []Record
	for rows.Next() {
		var r Record
		err := rows.Scan(&r.ID, &r.Hostname, &r.IP, &r.Type, &r.TTL)
		if err != nil {
			return nil, err
		}
		records = append(records, r)
	}
	return records, nil
}

func DeleteRecord(id int) error {
	_, err := DB.Exec("DELETE FROM records WHERE id = ?", id)
	return err
}
##FILE: C:\Projects\DNSManager\dns\dns.go
Go
package dns

import (
	"fmt"
	"log"
	"strings"
	"time"

	"DNSManager/database"
	"[github.com/miekg/dns](https://github.com/miekg/dns)"
)

func Start() error {
	server := &dns.Server{Addr: "0.0.0.0:53", Net: "udp"}
	dns.HandleFunc(".", handleDNSRequest)

	log.Println("Starting DNS server on port 53...")
	go func() {
		if err := server.ListenAndServe(); err != nil {
			log.Fatalf("Failed to start DNS server: %s\n", err.Error())
		}
	}()

	return nil
}

func handleDNSRequest(w dns.ResponseWriter, r *dns.Msg) {
	m := new(dns.Msg)
	m.SetReply(r)
	m.Compress = false
	m.Rcode = dns.RcodeSuccess

	if r.Opcode == dns.OpcodeQuery && len(r.Question) > 0 {
		q := r.Question[0]
		
		var qTypeStr string
		switch q.Qtype {
		case dns.TypeA:
			qTypeStr = "A"
		case dns.TypeAAAA:
			qTypeStr = "AAAA"
		case dns.TypeCNAME:
			qTypeStr = "CNAME"
		case dns.TypePTR:
			qTypeStr = "PTR"
		}

		targetHostname := strings.ToLower(strings.TrimSpace(q.Name))
		targetHostname = strings.TrimSuffix(targetHostname, ".")

		ip := ""
		if qTypeStr != "" {
			ip = lookupRecordInDB(targetHostname, qTypeStr)
		}

		if ip != "" {
			var rrStr string
			if qTypeStr == "CNAME" || qTypeStr == "PTR" {
				target := ip
				if !strings.HasSuffix(target, ".") {
					target += "."
				}
				rrStr = fmt.Sprintf("%s 60 IN %s %s", q.Name, qTypeStr, target)
			} else {
				rrStr = fmt.Sprintf("%s 60 IN %s %s", q.Name, qTypeStr, ip)
			}

			rr, err := dns.NewRR(rrStr)
			if err == nil {
				m.Answer = append(m.Answer, rr)
			}
			w.WriteMsg(m)
			return
		}

		if strings.HasSuffix(targetHostname, ".vgs") || strings.HasSuffix(targetHostname, "vgs.com") {
			if qTypeStr == "A" && !hostnameExistsInDB(targetHostname) {
				m.Rcode = dns.RcodeNameError
			}
			w.WriteMsg(m)
			return
		}

		client := new(dns.Client)
		client.Timeout = 2 * time.Second
		
		response, _, err := client.Exchange(r, "1.1.1.1:53")
		if err == nil && response != nil {
			w.WriteMsg(response)
			return
		}
	}

	w.WriteMsg(m)
}

func lookupRecordInDB(hostname string, recordType string) string {
	records, err := database.GetRecords()
	if err != nil {
		return ""
	}

	for _, record := range records {
		cleanDB := strings.ToLower(strings.TrimSpace(record.Hostname))
		cleanDB = strings.TrimSuffix(cleanDB, ".")

		if cleanDB == hostname && strings.ToUpper(record.Type) == recordType && cleanDB != "" {
			return record.IP
		}
	}
	return ""
}

func hostnameExistsInDB(hostname string) bool {
	records, err := database.GetRecords()
	if err != nil {
		return false
	}
	for _, record := range records {
		cleanDB := strings.ToLower(strings.TrimSpace(record.Hostname))
		cleanDB = strings.TrimSuffix(cleanDB, ".")
		if cleanDB == hostname && cleanDB != "" {
			return true
		}
	}
	return false
}
##FILE: C:\Projects\DNSManager\frontend\package.json
JSON
{
  "name": "frontend",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.56",
    "@types/react-dom": "^18.2.19",
    "@vitejs/plugin-react": "^4.2.1",
    "vite": "^5.1.4"
  }
}
##FILE: C:\Projects\DNSManager\frontend\src\main.jsx
JavaScript
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './style.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
##FILE: C:\Projects\DNSManager\frontend\src\style.css
CSS
body {
    margin: 0;
    padding: 0;
    background-color: #121824;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}
##FILE: C:\Projects\DNSManager\frontend\src\App.jsx
JavaScript
import { useEffect, useState } from 'react';
import {
    GetRecords,
    AddRecord,
    DeleteRecord
} from "../wailsjs/go/main/App";

function App() {
    const [activeTab, setActiveTab] = useState("main");
    const [records, setRecords] = useState([]);
    
    const [hostname, setHostname] = useState("");
    const [ip, setIp] = useState("");
    const [recordType, setRecordType] = useState("A");

    const [lookupQuery, setLookupQuery] = useState("");
    const [lookupResult, setLookupResult] = useState(null);
    const [hasSearched, setHasSearched] = useState(false);

    const [inventorySearch, setInventorySearch] = useState("");

    async function loadRecords() {
        try {
            const data = await GetRecords();
            setRecords(data || []);
        } catch (err) {
            console.error("Failed to sync records from data layer:", err);
        }
    }

    useEffect(() => {
        loadRecords();
    }, []);

    async function handleAddRecord() {
        if (!hostname || !ip) {
            alert("Mandatory Parameter Missing: Both Hostname identities and IP targets are required.");
            return;
        }

        try {
            await AddRecord(hostname, ip, recordType);
            alert(`Rule Context [${recordType}] safely committed for tracking.`);
            setHostname("");
            setIp("");
            loadRecords();
        } catch (err) {
            alert(err);
        }
    }

    async function handleDeleteRecord(id) {
        if (!window.confirm("Purge selected resolution track mapping permanently from internal store tables?")) {
            return;
        }

        try {
            await DeleteRecord(id);
            loadRecords();
        } catch (err) {
            alert(err);
        }
    }

    function handleLocalLookup() {
        if (!lookupQuery) {
            alert("Please input your verification string mapping query.");
            return;
        }

        setHasSearched(true);
        const cleanQuery = lookupQuery.trim().toLowerCase().replace(/\.$/, "");

        const found = records.filter(r => {
            const cleanDB = r.hostname.trim().toLowerCase().replace(/\.$/, "");
            return cleanDB === cleanQuery;
        });

        if (found.length > 0) {
            setLookupResult(found);
        } else {
            setLookupResult([]);
        }
    }

    const filteredInventory = records.filter(r => 
        r.hostname.toLowerCase().includes(inventorySearch.toLowerCase()) ||
        r.ip.toLowerCase().includes(inventorySearch.toLowerCase()) ||
        r.type.toLowerCase().includes(inventorySearch.toLowerCase())
    );

    return (
        <div style={{ padding: "30px", color: "#E0E0E0", backgroundColor: "#121824", minHeight: "100vh" }}>
            <div style={{ borderBottom: "2px solid #2A364F", paddingBottom: "15px", marginBottom: "20px" }}>
                <h1 style={{ margin: "0 0 5px 0", color: "#FFFFFF" }}>DNS Manager Console</h1>
                <h3 style={{ margin: "0 0 15px 0", color: "#8A99AD", fontWeight: "normal" }}>VGS Lab DNS Appliance Core</h3>
                
                <div style={{ display: "inline-block", backgroundColor: "#1A2333", padding: "10px 15px", borderRadius: "6px", border: "1px solid #2E3C54" }}>
                    <span style={{ color: "#4FFFB0", fontWeight: "bold" }}>● Appliance Active: </span>
                    <code style={{ color: "#FFF", fontSize: "14px" }}>local-dns-server-01.vgs.com</code> 
                    <span style={{ color: "#8A99AD" }}> ↔ Direct Host IP: </span>
                    <strong style={{ color: "#FFF" }}>192.168.31.87</strong>
                </div>
            </div>

            <div style={{ marginBottom: "25px", display: "flex", gap: "10px" }}>
                <button 
                    onClick={() => setActiveTab("main")} 
                    style={{
                        padding: "10px 20px", 
                        backgroundColor: activeTab === "main" ? "#3462FF" : "#1C2638", 
                        color: "#FFF", border: "none", borderRadius: "4px", fontWeight: "bold", cursor: "pointer"
                    }}
                >
                    🔍 Lookup & Create
                </button>
                <button 
                    onClick={() => setActiveTab("all")} 
                    style={{
                        padding: "10px 20px", 
                        backgroundColor: activeTab === "all" ? "#3462FF" : "#1C2638", 
                        color: "#FFF", border: "none", borderRadius: "4px", fontWeight: "bold", cursor: "pointer"
                    }}
                >
                    📋 Live Inventory Mappings ({records.length})
                </button>
            </div>

            {activeTab === "main" && (
                <div style={{ display: "flex", flexDirection: "column", gap: "30px" }}>
                    <div style={{ backgroundColor: "#1C2638", padding: "20px", borderRadius: "8px", border: "1px solid #2A364F" }}>
                        <h3 style={{ marginTop: "0", color: "#FFF" }}>Engine Resolution Query Matrix</h3>
                        <div style={{ display: "flex", gap: "10px", marginBottom: "15px" }}>
                            <input
                                placeholder="Query string (e.g. vc-01.vgs.com)"
                                value={lookupQuery}
                                onChange={(e) => setLookupQuery(e.target.value)}
                                style={{ padding: "10px", flex: 1, borderRadius: "4px", border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF" }}
                            />
                            <button onClick={handleLocalLookup} style={{ padding: "10px 20px", backgroundColor: "#4FFFB0", color: "#121824", fontWeight: "bold", border: "none", borderRadius: "4px", cursor: "pointer" }}>
                                Run Verification
                            </button>
                        </div>

                        {hasSearched && (
                            <div style={{ marginTop: "15px", padding: "12px", backgroundColor: "#121824", borderRadius: "6px", border: "1px solid #2E3C54" }}>
                                {lookupResult.length > 0 ? (
                                    <div>
                                        <h4 style={{ margin: "0 0 10px 0", color: "#4FFFB0" }}>✓ Matrix Resolution Valid:</h4>
                                        {lookupResult.map((res, index) => (
                                            <div key={index} style={{ fontFamily: "monospace", fontSize: "14px", padding: "4px 0" }}>
                                                <span style={{ color: "#FF9F43" }}>[{res.type}]</span> {res.hostname} ➜ <span style={{ color: "#4FFFB0" }}>{res.ip}</span> (TTL: {res.ttl}s)
                                            </div>
                                        ))}
                                    </div>
                                ) : (
                                    <div style={{ color: "#FF6B6B", fontWeight: "bold", fontFamily: "monospace" }}>
                                        🗙 STATUS NXDOMAIN: String context unassigned in SQLite repository layer.
                                    </div>
                                )}
                            </div>
                        )}
                    </div>

                    <div style={{ backgroundColor: "#1C2638", padding: "20px", borderRadius: "8px", border: "1px solid #2A364F" }}>
                        <h3 style={{ marginTop: "0", color: "#FFF" }}>Provision Infrastructure Records</h3>
                        <div style={{ display: "flex", flexWrap: "wrap", gap: "12px", alignItems: "center" }}>
                            <select 
                                value={recordType} 
                                onChange={(e) => setRecordType(e.target.value)}
                                style={{ padding: "10px", backgroundColor: "#121824", color: "#FFF", border: "1px solid #2A364F", borderRadius: "4px", fontWeight: "bold" }}
                            >
                                <option value="A">A (IPv4 Routing)</option>
                                <option value="AAAA">AAAA (IPv6 Routing)</option>
                                <option value="CNAME">CNAME (Alias Pointer)</option>
                                <option value="PTR">PTR (Reverse Lookup Map)</option>
                            </select>

                            <input
                                placeholder={recordType === "PTR" ? "IP Context Key" : "FQDN Host / Zone Name"}
                                value={hostname}
                                onChange={(e) => setHostname(e.target.value)}
                                style={{ padding: "10px", width: "250px", borderRadius: "4px", border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF" }}
                            />

                            <input
                                placeholder={recordType === "CNAME" || recordType === "PTR" ? "Canonical FQDN Target" : "Target Reference Address"}
                                value={ip}
                                onChange={(e) => setIp(e.target.value)}
                                style={{ padding: "10px", width: "180px", borderRadius: "4px", border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF" }}
                            />

                            <button onClick={handleAddRecord} style={{ padding: "10px 20px", backgroundColor: "#3462FF", color: "#FFF", fontWeight: "bold", border: "none", borderRadius: "4px", cursor: "pointer" }}>
                                Commit Record Context
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {activeTab === "all" && (
                <div style={{ backgroundColor: "#1C2638", padding: "20px", borderRadius: "8px", border: "1px solid #2A364F" }}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "15px", marginBottom: "20px" }}>
                        <h3 style={{ margin: "0", color: "#FFF", flex: 1 }}>Global Zone Database Registry</h3>
                        <input
                            placeholder="🔍 Dynamic Inventory Search (Type, host, or IP maps)..."
                            value={inventorySearch}
                            onChange={(e) => setInventorySearch(e.target.value)}
                            style={{ padding: "10px", width: "350px", borderRadius: "4px", border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF" }}
                        />
                    </div>

                    <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left" }}>
                        <thead>
                            <tr style={{ borderBottom: "2px solid #2A364F", color: "#8A99AD", fontSize: "14px" }}>
                                <th style={{ padding: "12px" }}>ID</th>
                                <th style={{ padding: "12px" }}>Record Type</th>
                                <th style={{ padding: "12px" }}>Lookup Source Key</th>
                                <th style={{ padding: "12px" }}>Translation Value Matrix</th>
                                <th style={{ padding: "12px" }}>Operational Rules</th>
                            </tr>
                        </thead>
                        <tbody>
                            {filteredInventory.length > 0 ? (
                                filteredInventory.map((record) => (
                                    <tr key={record.id} style={{ borderBottom: "1px solid #2A364F", fontSize: "14px", backgroundColor: "#17202F" }}>
                                        <td style={{ padding: "12px", color: "#8A99AD" }}>{record.id}</td>
                                        <td style={{ padding: "12px" }}>
                                            <span style={{ backgroundColor: "#121824", color: "#4FFFB0", padding: "4px 8px", borderRadius: "4px", border: "1px solid #2E3C54", fontWeight: "bold" }}>{record.type}</span>
                                        </td>
                                        <td style={{ padding: "12px", fontFamily: "monospace" }}>{record.hostname}</td>
                                        <td style={{ padding: "12px", fontFamily: "monospace", color: "#4FFFB0" }}>{record.ip}</td>
                                        <td style={{ padding: "12px" }}>
                                            <button onClick={() => handleDeleteRecord(record.id)} style={{ backgroundColor: "#FF6B6B", color: "#FFF", border: "none", padding: "6px 12px", borderRadius: "4px", cursor: "pointer", fontWeight: "bold" }}>Purge</button>
                                        </td>
                                    </tr>
                                ))
                            ) : (
                                <tr>
                                    <td colSpan="5" style={{ padding: "20px", textAlign: "center", color: "#8A99AD", fontStyle: "italic" }}>No active matching infrastructure mappings discovered.</td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}

export default App;
🚀 Workstation Alignment & Operational Verification
To routing host operational system requests cleanly through your newly deployed local DNS appliance, apply these system networking adapter policies within an administrator terminal session:

1. Apply PowerShell DNS Interface Rules
PowerShell
# Map your active network adapter's primary DNS address to your target appliance host IP
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("192.168.31.87", "1.1.1.1")

# Disable standard IPv6 bindings to guarantee lookups are directed to the IPv4 UDP 53 socket
Disable-NetAdapterBinding -Name "Wi-Fi" -ComponentID ms_tcpip6

# Flush old system resolution maps out of local memory cache
Clear-DnsClientCache
2. Verify Operational Performance
Execute basic diagnostics against the engine to ensure both split-horizon paths resolve properly:

PowerShell
# Test Local SQLite Resolution Strategy (Should yield target lab record mapped in UI)
nslookup dns-server-01.vgs.com

# Test Public Internet Proxy Routing Path (Should yield public upstream Cloudflare maps)
nslookup google.com
📦 System Compilation & Repository Lifecycle
Initialize node assets, synchronize dependencies, and push structural baseline frames straight into remote GitHub code trees:

PowerShell
# Sync core dependencies, initialize frontend libraries and launch the dev watcher environment
cd C:\Projects\DNSManager
go mod tidy
cd frontend
npm install
cd ..
wails dev

# Code Versioning Execution Commands
git init
git add .
git commit -m "feat: complete split-horizon dns appliance with modernc pure-go sqlite engine and react workspace UI"
git branch -M main
git remote add origin [https://github.com/YOUR_USERNAME/DNSManager.git](https://github.com/YOUR_USERNAME/DNSManager.git)
git push -u origin main
