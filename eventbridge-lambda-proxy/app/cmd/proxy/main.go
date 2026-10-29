// Command proxy runs as a Lambda when AWS_LAMBDA_RUNTIME_API is set
// (EventBridge invokes it), and as a plain HTTP server otherwise (local dev).
package main

import (
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/lambda"

	"github.com/t10e/infra-sandbox/eventbridge-lambda-proxy/internal/proxy"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	timeout, err := time.ParseDuration(env("TARGET_TIMEOUT", "10s"))
	if err != nil {
		slog.Error("bad TARGET_TIMEOUT", "err", err)
		os.Exit(1)
	}
	cfg := proxy.Config{
		TargetURL:   os.Getenv("TARGET_URL"),
		ReportTypes: proxy.ParseReportTypes(env("REPORT_TYPES", "a,b")),
		Timeout:     timeout,
	}
	if cfg.TargetURL == "" {
		slog.Error("TARGET_URL is required")
		os.Exit(1)
	}

	// One client per process so warm invocations reuse connections.
	engine := proxy.NewEngine(cfg, &http.Client{})

	if os.Getenv("AWS_LAMBDA_RUNTIME_API") != "" {
		lambda.Start(proxy.NewHandler(engine))
		return
	}

	addr := env("ADDR", "127.0.0.1:8080")
	slog.Info("local mode", "addr", addr, "target", cfg.TargetURL)
	if err := http.ListenAndServe(addr, engine); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
