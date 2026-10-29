// Command echo is the stand-in target behind a Lambda Function URL. It logs
// what it received and when, so delivery latency can be read from its logs.
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

type report struct {
	ReportType string `json:"report_type"`
	EventID    string `json:"event_id"`
	Time       string `json:"time"`
	Trigger    string `json:"trigger"`
}

func handle(_ context.Context, req events.LambdaFunctionURLRequest) (events.LambdaFunctionURLResponse, error) {
	received := time.Now().UTC()

	var r report
	_ = json.Unmarshal([]byte(req.Body), &r)

	// Function URLs lower-case header names.
	attrs := []any{
		"path", req.RawPath,
		"report_type", req.Headers["x-report-type"],
		"idempotency_key", req.Headers["x-idempotency-key"],
		"trigger", r.Trigger,
		"event_time", r.Time,
		"received_at", received.Format(time.RFC3339Nano),
	}
	if t, err := time.Parse(time.RFC3339, r.Time); err == nil {
		attrs = append(attrs, "delivery_ms", received.Sub(t).Milliseconds())
	}
	slog.Info("report received", attrs...)

	out, _ := json.Marshal(map[string]any{"received_at": received, "path": req.RawPath, "report": r})
	return events.LambdaFunctionURLResponse{
		StatusCode: 200,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(out),
	}, nil
}

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	lambda.Start(handle)
}
