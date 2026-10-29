package proxy

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"

	"github.com/gin-gonic/gin"
)

// Event is the payload every EventBridge rule sends, shaped by the rule's
// input_transformer so schedule and on-demand triggers look the same.
type Event struct {
	ReportType string `json:"report_type"`
	EventID    string `json:"event_id"`
	Time       string `json:"time"`
	Trigger    string `json:"trigger"`
}

// NewHandler returns the Lambda handler. It turns the event into an HTTP
// request and runs it through the Gin engine, so Lambda and local dev share
// one code path.
//
// A returned error makes Lambda's async invoke retry the event, so only
// failures that can succeed later return one. Other failures are logged and
// dropped.
func NewHandler(engine *gin.Engine) func(context.Context, Event) error {
	return func(ctx context.Context, ev Event) error {
		if ev.ReportType == "" {
			slog.Error("dropped event without report_type", "event_id", ev.EventID)
			return nil
		}

		body, err := json.Marshal(ev)
		if err != nil {
			return fmt.Errorf("marshal event: %w", err)
		}
		req := httptest.NewRequestWithContext(ctx, http.MethodPost,
			"/reports/"+url.PathEscape(ev.ReportType), bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		if ev.EventID != "" {
			req.Header.Set(HeaderIdempotencyKey, ev.EventID)
		}

		rec := httptest.NewRecorder()
		engine.ServeHTTP(rec, req)

		switch {
		case rec.Code < 300:
			return nil
		case Retryable(rec.Code):
			return errors.New(describe(rec.Code, rec.Body.Bytes()))
		default:
			slog.Error("dropped event, not retryable",
				"report_type", ev.ReportType,
				"event_id", ev.EventID,
				"detail", describe(rec.Code, rec.Body.Bytes()),
			)
			return nil
		}
	}
}
