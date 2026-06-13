package config

import "os"

type Config struct {
	Provider string
	Model    string
	APIKey   string
}

func Load() Config {
	return Config{
		Provider: getEnv("AGENT_PROVIDER", "openai"),
		Model:    getEnv("AGENT_MODEL", "gpt-4o"),
		APIKey:   os.Getenv("AGENT_API_KEY"),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
