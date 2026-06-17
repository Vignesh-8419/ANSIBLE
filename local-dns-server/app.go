package main

import (
	"context"
	"fmt"

	"local-dns-server/database"
	"local-dns-server/dns"
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