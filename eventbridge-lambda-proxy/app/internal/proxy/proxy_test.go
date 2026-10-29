package proxy

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type captured struct {
	path, method, idempotencyKey, reportType string
	body                                     Event
}

// target starts a fake upstream that records each request and answers with status.
func target(t *testing.T, status int, delay time.Duration) (*httptest.Server, *[]captured) {
	t.Helper()
	var mu sync.Mutex
	got := &[]captured{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(delay)
		raw, _ := io.ReadAll(r.Body)
		var ev Event
		_ = json.Unmarshal(raw, &ev)
		mu.Lock()
		*got = append(*got, captured{r.URL.Path, r.Method, r.Header.Get(HeaderIdempotencyKey), r.Header.Get(HeaderReportType), ev})
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	t.Cleanup(srv.Close)
	return srv, got
}

func handler(targetURL string, timeout time.Duration) func(context.Context, Event) error {
	cfg := Config{TargetURL: targetURL, ReportTypes: ParseReportTypes("a, b"), Timeout: timeout}
	return NewHandler(NewEngine(cfg, &http.Client{}))
}

func TestForwardsKnownType(t *testing.T) {
	srv, got := target(t, http.StatusOK, 0)
	ev := Event{ReportType: "a", EventID: "evt-1", Time: "2026-10-28T00:00:00Z", Trigger: "schedule"}

	if err := handler(srv.URL+"/", time.Second)(context.Background(), ev); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(*got) != 1 {
		t.Fatalf("want 1 upstream call, got %d", len(*got))
	}
	c := (*got)[0]
	if c.method != http.MethodPost || c.path != "/reports/a" {
		t.Errorf("want POST /reports/a, got %s %s", c.method, c.path)
	}
	if c.idempotencyKey != "evt-1" || c.reportType != "a" {
		t.Errorf("headers: idempotency=%q report_type=%q", c.idempotencyKey, c.reportType)
	}
	if c.body != ev {
		t.Errorf("body: want %+v, got %+v", ev, c.body)
	}
}

func TestUnknownTypeIsNotForwarded(t *testing.T) {
	srv, got := target(t, http.StatusOK, 0)
	for _, rt := range []string{"c", "../a", "a/../b", ""} {
		if err := handler(srv.URL, time.Second)(context.Background(), Event{ReportType: rt}); err != nil {
			t.Errorf("type %q: unknown type must be dropped without retry, got %v", rt, err)
		}
	}
	if len(*got) != 0 {
		t.Fatalf("unknown types reached upstream: %+v", *got)
	}
}

func TestUpstreamFailures(t *testing.T) {
	cases := []struct {
		name      string
		status    int
		delay     time.Duration
		wantRetry bool
	}{
		{"5xx retries", http.StatusServiceUnavailable, 0, true},
		{"429 retries", http.StatusTooManyRequests, 0, true},
		{"4xx dropped", http.StatusUnprocessableEntity, 0, false},
		{"timeout retries", http.StatusOK, 300 * time.Millisecond, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			srv, _ := target(t, tc.status, tc.delay)
			err := handler(srv.URL, 100*time.Millisecond)(context.Background(), Event{ReportType: "b", EventID: "evt-2"})
			if (err != nil) != tc.wantRetry {
				t.Fatalf("wantRetry=%v, err=%v", tc.wantRetry, err)
			}
		})
	}
}

func TestUnreachableTargetRetries(t *testing.T) {
	err := handler("http://127.0.0.1:1", time.Second)(context.Background(), Event{ReportType: "a"})
	if err == nil || !strings.Contains(err.Error(), "502") {
		t.Fatalf("want 502 error, got %v", err)
	}
}

func TestHTTPRoute(t *testing.T) {
	srv, got := target(t, http.StatusCreated, 0)
	engine := NewEngine(Config{TargetURL: srv.URL, ReportTypes: ParseReportTypes("a"), Timeout: time.Second}, &http.Client{})

	req := httptest.NewRequest(http.MethodPost, "/reports/a", strings.NewReader(`{"report_type":"a"}`))
	req.Header.Set(HeaderIdempotencyKey, "manual-1")
	rec := httptest.NewRecorder()
	engine.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("want upstream status 201 passed through, got %d", rec.Code)
	}
	if len(*got) != 1 || (*got)[0].idempotencyKey != "manual-1" {
		t.Fatalf("upstream calls: %+v", *got)
	}
}
