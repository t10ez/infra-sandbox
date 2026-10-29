// Package proxy holds the Gin engine that forwards report requests to the
// target URL, and the adapter that feeds EventBridge events into it.
package proxy

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	HeaderIdempotencyKey = "X-Idempotency-Key"
	HeaderReportType     = "X-Report-Type"
	maxBodyBytes         = 1 << 20
)

type Config struct {
	TargetURL   string
	ReportTypes map[string]bool
	Timeout     time.Duration
}

// ParseReportTypes turns "a,b" into a set. Blank entries are dropped.
func ParseReportTypes(s string) map[string]bool {
	set := map[string]bool{}
	for _, t := range strings.Split(s, ",") {
		if t = strings.TrimSpace(t); t != "" {
			set[t] = true
		}
	}
	return set
}

func NewEngine(cfg Config, client *http.Client) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	r.GET("/healthz", func(c *gin.Context) { c.String(http.StatusOK, "ok") })
	r.POST("/reports/:type", func(c *gin.Context) { forward(c, cfg, client) })
	return r
}

func forward(c *gin.Context, cfg Config, client *http.Client) {
	reportType := c.Param("type")
	if !cfg.ReportTypes[reportType] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unknown report type", "report_type": reportType})
		return
	}

	body, err := io.ReadAll(io.LimitReader(c.Request.Body, maxBodyBytes))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "read body: " + err.Error()})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), cfg.Timeout)
	defer cancel()

	url := strings.TrimRight(cfg.TargetURL, "/") + "/reports/" + reportType
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "build request: " + err.Error()})
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set(HeaderReportType, reportType)
	if key := c.GetHeader(HeaderIdempotencyKey); key != "" {
		req.Header.Set(HeaderIdempotencyKey, key)
	}

	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		status := http.StatusBadGateway
		if errors.Is(err, context.DeadlineExceeded) {
			status = http.StatusGatewayTimeout
		}
		slog.Error("upstream request failed", "report_type", reportType, "url", url, "err", err)
		c.JSON(status, gin.H{"error": "upstream: " + err.Error()})
		return
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, maxBodyBytes))
	slog.Info("forwarded",
		"report_type", reportType,
		"idempotency_key", c.GetHeader(HeaderIdempotencyKey),
		"upstream_status", resp.StatusCode,
		"upstream_ms", time.Since(start).Milliseconds(),
	)

	ct := resp.Header.Get("Content-Type")
	if ct == "" {
		ct = "application/octet-stream"
	}
	c.Data(resp.StatusCode, ct, respBody)
}

// Retryable reports whether a failed status is worth an EventBridge retry.
// 5xx and 429 may succeed later; other 4xx will fail the same way again.
func Retryable(status int) bool {
	return status >= 500 || status == http.StatusTooManyRequests
}

func describe(status int, body []byte) string {
	b := string(body)
	if len(b) > 512 {
		b = b[:512] + "..."
	}
	return fmt.Sprintf("status %d: %s", status, b)
}
