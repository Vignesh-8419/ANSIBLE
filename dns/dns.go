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

		// 1. Try to find the record in our local SQLite database first
		ip := ""
		if qTypeStr != "" {
			ip = lookupRecordInDB(targetHostname, qTypeStr)
		}

		if ip != "" {
			// Found locally! Construct our answer
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

		// 2. If it's a local lab domain (.vgs or .local) but not found, return NXDOMAIN immediately
		if strings.HasSuffix(targetHostname, ".vgs") || strings.HasSuffix(targetHostname, "vgs.com") {
			if qTypeStr == "A" && !hostnameExistsInDB(targetHostname) {
				m.Rcode = dns.RcodeNameError
			}
			w.WriteMsg(m)
			return
		}

		// 3. INTERNET FORWARDER: It's a public domain (google.com, etc.). Forward it to 1.1.1.1
		client := new(dns.Client)
		client.Timeout = 2 * time.Second
		
		// Send the exact query package to Cloudflare upstream DNS over UDP
		response, _, err := client.Exchange(r, "1.1.1.1:53")
		if err == nil && response != nil {
			w.WriteMsg(response) // Pass the real internet answer right back to Windows!
			return
		}
	}

	// Fallback empty response
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