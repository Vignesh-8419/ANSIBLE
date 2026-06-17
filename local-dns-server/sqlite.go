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
	Type     string `json:"type"` // Added: A, AAAA, CNAME, PTR
	TTL      int    `json:"ttl"`
}

func Init() error {
	var err error

	DB, err = sql.Open("sqlite", "records.db")
	if err != nil {
		return err
	}

	// Updated table schema to include record type
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