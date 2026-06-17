Here is a comprehensive, production-ready documentation file structured perfectly for your project. This contains a high-level system overview, configuration requirements for your virtualization environments, and a complete code catalog of every critical file in your workspace so you can keep your repository fully tracked.

Step 1: Overwrite your README.md File
Run this command in your Administrator PowerShell to quickly open your readme file:

PowerShell
notepad.exe C:\Projects\DNSManager\README.md
Delete any old placeholder text, paste the entire block below, save, and close.

Markdown
# VGS Lab DNS Appliance (DNSManager)

An enterprise-grade, split-horizon local DNS appliance built with **Go**, **Wails (Vite + React)**, and **SQLite**. 

This application functions as a local infrastructure gateway for homelabs or development environments. It allows administrators to dynamically provision localized core records (`A`, `AAAA`, `CNAME`, `PTR`) for hypervisors (VMware ESXi, vCenter) and Linux clusters (Rocky Linux, CentOS) while seamlessly forwarding all public requests to upstream internet DNS authorities.

---

## 🚀 Key Features
* **Split-Horizon Architecture**: Internal enterprise zone queries (`.vgs`, `vgs.com`) resolve instantly out of a highly lightweight local SQLite database.
* **Integrated Upstream Forwarder**: Real-time failover routing transparently passes public internet domain requests (`google.com`, `github.com`) to Cloudflare (`1.1.1.1`).
* **Multi-Type DNS Support**: Complete support for provisioning `A` (IPv4), `AAAA` (IPv6), `CNAME` (Aliases), and `PTR` (Reverse Lookup) pointer fields.
* **Modern Isolated UX**: Isolated utility lookup matrix dashboard separate from the complete searchable global inventory database page.

---

## 🛠️ Local Host & Lab Machine Configuration

To transition your system from passing explicit IP endpoints during lookups (`nslookup host <IP>`) to evaluating native short commands (`nslookup host`), apply the following architectural alignments.

### 1. Windows Management Host Configuration
Open **PowerShell as an Administrator** and apply static binding rules directly to your active network card interface to route your laptop's interface traffic through your running Wails backend application context loop:

```powershell
# Assign primary interface lookup to your local appliance binding address
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("192.168.31.87", "1.1.1.1")

# Disable IPv6 DNS binding adjustments to stop ISP router overrides
Disable-NetAdapterBinding -Name "Wi-Fi" -ComponentID ms_tcpip6

# Flush system memory resolver state cache maps
Clear-DnsClientCache
2. VMware Virtual Machine Guest Network Configuration
Ensure your target guest VMs are deployed on a Bridged Virtual Switch (VMnet0) sharing the primary host interface card framework.

For Rocky Linux / CentOS 8+ nodes:
Bash
# Modify connection network maps (replace ens33 with your adapter profile)
sudo nmcli connection modify ens33 ipv4.dns "192.168.31.87"
sudo nmcli connection up ens33
For VMware ESXi Hypervisors:
Access the ESXi Host Client Web UI Console.

Navigate to Networking ➔ TCP/IP Stacks ➔ Default TCP/IP Stack ➔ Edit Settings.

Set Primary DNS Server to your running appliance node address: 192.168.31.87.

🖥️ Development Lifecycle & Execution Commands
Run these core operational terminal actions within the project base root directory (C:\Projects\DNSManager):

PowerShell
# Drop tracking data artifacts to clear testing storage state configurations
Remove-Item -Force .\records.db

# Clear Wails compilation storage artifacts and dependency trees
wails clean

# Run compiling asset watcher loop in live debug execution context mode
wails dev

---

### Step 2: The Complete Project Code Catalog

Below is the exact blueprint of every file currently active in your directory tree. Keep this structural manifest safe or commit it inside a `/docs` sub-folder in your git tree.

### 📋 Backend File Architecture

#### 1. `.\main.go`
```go
package main

import (
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
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
2. .\app.go
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
3. .\database\sqlite.go
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
4. .\dns\dns.go
Go
package dns

import (
	"fmt"
	"log"
	"strings"
	"time"

	"DNSManager/database"
	"github.com/miekg/dns"
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
⚛️ Frontend UI Architecture
5. .\frontend\src\App.jsx
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
            console.error("Failed to load records:", err);
        }
    }

    useEffect(() => {
        loadRecords();
    }, []);

    async function handleAddRecord() {
        if (!hostname || !ip) {
            alert("Both Hostname and IP/Target are required!");
            return;
        }

        try {
            await AddRecord(hostname, ip, recordType);
            alert(`Successfully added ${recordType} record for ${hostname}`);
            setHostname("");
            setIp("");
            loadRecords();
        } catch (err) {
            alert(err);
        }
    }

    async function handleDeleteRecord(id) {
        if (!window.confirm("Are you sure you want to delete this DNS record?")) {
            return;
        }

        try {
            await DeleteRecord(id);
            loadRecords();
        } catch (err) {
            alert(err);
        }
    }

    // Front-end fast inventory database lookup engine simulation method
    function handleLocalLookup() {
        if (!lookupQuery) {
            alert("Please enter a hostname to lookup");
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
        <div style={{ padding: "30px", fontFamily: "Arial, sans-serif", color: "#E0E0E0", backgroundColor: "#121824", minHeight: "100vh" }}>
            <div style={{ borderBottom: "2px solid #2A364F", paddingBottom: "15px", marginBottom: "20px" }}>
                <h1 style={{ margin: "0 0 5px 0", color: "#FFFFFF" }}>DNS Manager</h1>
                <h3 style={{ margin: "0 0 15px 0", color: "#8A99AD", fontWeight: "normal" }}>VGS Lab DNS Appliance</h3>
                
                <div style={{ display: "inline-block", backgroundColor: "#1A2333", padding: "10px 15px", borderRadius: "6px", border: "1px solid #2E3C54" }}>
                    <span style={{ color: "#4FFFB0", fontWeight: "bold" }}>● Active DNS Engine: </span>
                    <code style={{ color: "#FFF", fontSize: "14px" }}>local-dns-server-01.vgs.com</code> 
                    <span style={{ color: "#8A99AD" }}> ↔ IP: </span>
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
                    📋 All DNS Entries ({records.length})
                </button>
            </div>

            {activeTab === "main" && (
                <div style={{ display: "flex", flexDirection: "column", gap: "30px" }}>
                    <div style={{ backgroundColor: "#1C2638", padding: "20px", borderRadius: "8px", border: "1px solid #2A364F" }}>
                        <h3 style={{ marginTop: "0", color: "#FFF" }}>DNS Record Lookup Tool</h3>
                        <div style={{ display: "flex", gap: "10px", marginBottom: "15px" }}>
                            <input
                                placeholder="Enter hostname to query (e.g. dns-server-01.vgs.com)"
                                value={lookupQuery}
                                onChange={(e) => setLookupQuery(e.target.value)}
                                style={{ padding: "10px", flex: 1, borderRadius: "4px", border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF" }}
                            />
                            <button onClick={handleLocalLookup} style={{ padding: "10px 20px", backgroundColor: "#4FFFB0", color: "#121824", fontWeight: "bold", border: "none", borderRadius: "4px", cursor: "pointer" }}>
                                Query Appliance
                            </button>
                        </div>

                        {hasSearched && (
                            <div style={{ marginTop: "15px", padding: "12px", backgroundColor: "#121824", borderRadius: "6px", border: "1px solid #2E3C54" }}>
                                {lookupResult.length > 0 ? (
                                    <div>
                                        <h4 style={{ margin: "0 0 10px 0", color: "#4FFFB0" }}>✓ Record Found:</h4>
                                        {lookupResult.map((res, index) => (
                                            <div key={index} style={{ fontFamily: "monospace", fontSize: "14px", padding: "4px 0" }}>
                                                <span style={{ color: "#FF9F43" }}>[{res.type}]</span> {res.hostname} ➜ <span style={{ color: "#4FFFB0" }}>{res.ip}</span> (TTL: {res.ttl}s)
                                            </div>
                                        ))}
                                    </div>
                                ) : (
                                    <div style={{ color: "#FF6B6B", fontWeight: "bold", fontFamily: "monospace" }}>
                                        🗙 NXDOMAIN: Hostname entry not mapped in SQLite repository.
                                    </div>
                                )}
                            </div>
                        )}
                    </div>

                    <div style={{ backgroundColor: "#1C2638", padding: "20px", borderRadius: "8px", border: "1px solid #2A364F" }}>
                        <h3 style={{ marginTop: "0", color: "#FFF" }}>Provision New DNS Record</h3>
                        <div style={{ display: "flex", flexWrap: "wrap", gap: "12px", alignItems: "center" }}>
                            <select 
                                value={recordType} 
                                onChange={(e) => setRecordType(e.target.value)}
                                style={{ padding: "10px", backgroundColor: "#121824", color: "#FFF", border: "1px solid #2A364F", borderRadius: "4px", fontWeight: "bold" }}
                            >
                                <option value="A">A (IPv4)</option>
                                <option value="AAAA">AAAA (IPv6)</option>
                                <option value="CNAME">CNAME (Alias)</option>
                                <option value="PTR">PTR (Reverse DNS)</option>
                            </select>

                            <input
                                placeholder={recordType === "PTR" ? "IP Target Key" : "Hostname / Zone Context"}
                                value={hostname}
                                onChange={(e) => setHostname(e.target.value)}
                                style={{ padding: "10px", width: "250px", borderRadius: "4px", border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF" }}
                            />

                            <input
                                placeholder={recordType === "CNAME" || recordType === "PTR" ? "Target Pointer FQDN" : "Destination IP Address"}
                                value={ip}
                                onChange={(e) => setIp(e.target.value)}
                                style={{ padding: "10px", width: "180px", borderRadius: "4px", border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF" }}
                            />

                            <button onClick={handleAddRecord} style={{ padding: "10px 20px", backgroundColor: "#3462FF", color: "#FFF", fontWeight: "bold", border: "none", borderRadius: "4px", cursor: "pointer" }}>
                                Commit Record
                            </button>
                        </div>
                        <p style={{ fontSize: "12px", color: "#8A99AD", marginTop: "10px", marginBottom: "0" }}>
                            *Records committed here are written directly to production SQLite tables without altering active view display metrics.
                        </p>
                    </div>
                </div>
            )}

            {activeTab === "all" && (
                <div style={{ backgroundColor: "#1C2638", padding: "20px", borderRadius: "8px", border: "1px solid #2A364F" }}>
                    <div style={{ display: "flex", justifyContent: "between", alignItems: "center", flexWrap: "wrap", gap: "15px", marginBottom: "20px" }}>
                        <h3 style={{ margin: "0", color: "#FFF", flex: 1 }}>Global DNS Inventory Mapping</h3>
                        <input
                            placeholder="🔍 Dynamic Inventory Search (Filter by Host, IP, or Type)..."
                            value={inventorySearch}
                            onChange={(e) => setInventorySearch(e.target.value)}
                            style={{ padding: "10px", width: "350px", borderRadius: "4px", border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF" }}
                        />
                    </div>

                    <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left" }}>
                        <thead>
                            <tr style={{ borderBottom: "2px solid #2A364F", color: "#8A99AD", fontSize: "14px" }}>
                                <th style={{ padding: "12px" }}>ID</th>
                                <th style={{ padding: "12px" }}>Type</th>
                                <th style={{ padding: "12px" }}>Hostname / Lookup Identifier</th>
                                <th style={{ padding: "12px" }}>Target Translation / Routing IP</th>
                                <th style={{ padding: "12px" }}>Action</th>
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
                                    <td colSpan="5" style={{ padding: "20px", textAlign: "center", color: "#8A99AD", fontStyle: "italic" }}>No active matching infrastructure mappings found.</td>
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
Step 3: Pushing Your Project to GitHub
Ready to store everything in your remote source control repository? Run this simple, standard Git sequence inside your directory terminal to initialize, stage, and deliver your codebase up to your GitHub dashboard profile:

PowerShell
# Initialize git workspace inside your root directory context
git init

# Stage all manifest items, file blueprints, and documentation trees
git add .

# Add a commit tracking snapshot signature to save this build state
git commit -m "feat: complete split-horizon dns appliance with type management and query view isolation"

# Set main as the primary deployment branch path
git branch -M main

# Link your local workstation folder files directly to your remote repository URL address
# (Swap out your real remote GitHub URL below)
git remote add origin https://github.com/YOUR_USERNAME/DNSManager.git

# Securely push your codebase files right up to GitHub production server storage paths
git push -u origin main
