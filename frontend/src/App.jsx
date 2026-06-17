import { useEffect, useState } from 'react';
import {
    GetRecords,
    AddRecord,
    DeleteRecord
} from "../wailsjs/go/main/App";

function App() {
    // Navigation State: 'main' (Lookup/Create) or 'all' (Database Inventory)
    const [activeTab, setActiveTab] = useState("main");

    // Shared Database State
    const [records, setRecords] = useState([]);
    
    // Create Record Form State
    const [hostname, setHostname] = useState("");
    const [ip, setIp] = useState("");
    const [recordType, setRecordType] = useState("A");

    // Local Lookup/Search State
    const [lookupQuery, setLookupQuery] = useState("");
    const [lookupResult, setLookupResult] = useState(null);
    const [hasSearched, setHasSearched] = useState(false);

    // Global Inventory Search Filter State
    const [inventorySearch, setInventorySearch] = useState("");

    // Load Records from SQLite Database
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

    // Add a Record to DB
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
            loadRecords(); // Refresh global cache
        } catch (err) {
            alert(err);
        }
    }

    // Delete a Record from DB
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

    // Perform Local GUI Lookup
    function handleLocalLookup() {
        if (!lookupQuery) {
            alert("Please enter a hostname to lookup");
            return;
        }

        setHasSearched(true);
        const cleanQuery = lookupQuery.trim().toLowerCase().replace(/\.$/, "");

        // Filter through loaded records for an exact match
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

    // Filtered list for the "All Entries" inventory page
    const filteredInventory = records.filter(r => 
        r.hostname.toLowerCase().includes(inventorySearch.toLowerCase()) ||
        r.ip.toLowerCase().includes(inventorySearch.toLowerCase()) ||
        r.type.toLowerCase().includes(inventorySearch.toLowerCase())
    );

    return (
        <div style={{ padding: "30px", fontFamily: "Arial, sans-serif", color: "#E0E0E0", backgroundColor: "#121824", minHeight: "100vh" }}>
            
            {/* Header Banner & Active Server Details */}
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

            {/* Navigation Tabs Bar */}
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

            {/* TAB 1: LOOKUP & CREATE (MAIN VIEW) */}
            {activeTab === "main" && (
                <div style={{ display: "flex", flexDirection: "column", gap: "30px" }}>
                    
                    {/* section A: DNS Lookup Engine */}
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

                        {/* Lookup Results Dashboard */}
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

                    {/* Section B: Create Record Input Engine */}
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

            {/* TAB 2: INVENTORY LIST (SEPARATE VIEW PAGE) */}
            {activeTab === "all" && (
                <div style={{ backgroundColor: "#1C2638", padding: "20px", borderRadius: "8px", border: "1px solid #2A364F" }}>
                    <div style={{ display: "flex", justifyContent: "between", alignItems: "center", flexWrap: "wrap", gap: "15px", marginBottom: "20px" }}>
                        <h3 style={{ margin: "0", color: "#FFF", flex: 1 }}>Global DNS Inventory Mapping</h3>
                        
                        {/* Interactive Search Engine Filter */}
                        <input
                            placeholder="🔍 Dynamic Inventory Search (Filter by Host, IP, or Type)..."
                            value={inventorySearch}
                            onChange={(e) => setInventorySearch(e.target.value)}
                            style={{
                                padding: "10px", width: "350px", borderRadius: "4px", 
                                border: "1px solid #2A364F", backgroundColor: "#121824", color: "#FFF"
                            }}
                        />
                    </div>

                    {/* Records Inventory Matrix */}
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
                                            <span style={{ 
                                                backgroundColor: "#121824", color: "#4FFFB0", padding: "4px 8px", 
                                                borderRadius: "4px", border: "1px solid #2E3C54", fontWeight: "bold" 
                                            }}>{record.type}</span>
                                        </td>
                                        <td style={{ padding: "12px", fontFamily: "monospace" }}>{record.hostname}</td>
                                        <td style={{ padding: "12px", fontFamily: "monospace", color: "#4FFFB0" }}>{record.ip}</td>
                                        <td style={{ padding: "12px" }}>
                                            <button 
                                                onClick={() => handleDeleteRecord(record.id)} 
                                                style={{ 
                                                    backgroundColor: "#FF6B6B", color: "#FFF", border: "none", 
                                                    padding: "6px 12px", borderRadius: "4px", cursor: "pointer", fontWeight: "bold" 
                                                }}
                                            >
                                                Purge
                                            </button>
                                        </td>
                                    </tr>
                                ))
                            ) : (
                                <tr>
                                    <td colSpan="5" style={{ padding: "20px", textAlign: "center", color: "#8A99AD", fontStyle: "italic" }}>
                                        No active matching infrastructure mappings found.
                                    </td>
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