package rootbridge

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestAuthenticatedBridgePreservesEnvelopesAndSurvivesReconnect(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	var mu sync.Mutex
	var events func([]byte)
	var calls [][]byte
	server := &Server{Token: strings.Repeat("a", 64), Events: func(sink func([]byte)) {
		mu.Lock()
		events = sink
		mu.Unlock()
	}, Invoke: func(data []byte, reply func([]byte)) {
		mu.Lock()
		calls = append(calls, bytes.Clone(data))
		mu.Unlock()
		reply([]byte(`{"id":"ui-1","result":{"node":"测试","selected":true}}`))
	}}
	go func() { _ = server.Serve(listener) }()
	connect := func(token string) net.Conn {
		conn, err := net.Dial("tcp4", listener.Addr().String())
		if err != nil {
			t.Fatal(err)
		}
		_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
		hello, _ := json.Marshal(map[string]string{"token": token})
		if err := WriteFrame(conn, hello); err != nil {
			t.Fatal(err)
		}
		return conn
	}
	unauthorized := connect(strings.Repeat("b", 64))
	if _, err := ReadFrame(unauthorized); err == nil {
		t.Fatal("unauthorized peer admitted")
	}
	_ = unauthorized.Close()
	for attempt := 0; attempt < 2; attempt++ {
		conn := connect(server.Token)
		if ack, err := ReadFrame(conn); err != nil || string(ack) != `{"ready":true}` {
			t.Fatalf("handshake: %s %v", ack, err)
		}
		request := []byte(`{"id":"ui-1","method":"changeProxy","arguments":{"group-name":"代理","proxy-name":"测试"}}`)
		if err := WriteFrame(conn, request); err != nil {
			t.Fatal(err)
		}
		answer, err := ReadFrame(conn)
		if err != nil || !bytes.Contains(answer, []byte(`"result":{"node":`)) {
			t.Fatalf("response double-encoded: %s %v", answer, err)
		}
		mu.Lock()
		sink := events
		mu.Unlock()
		event := []byte(`{"method":"message","arguments":[{"type":"routeChanged","data":{"picks-version":2}}]}`)
		sink(event)
		got, err := ReadFrame(conn)
		if err != nil || !bytes.Equal(got, event) {
			t.Fatalf("event changed: %s %v", got, err)
		}
		mu.Lock()
		actual := calls[len(calls)-1]
		mu.Unlock()
		if !bytes.Equal(actual, request) {
			t.Fatal("method or arguments changed in transport")
		}
		_ = conn.Close()
	}
}

type fragmentWriter struct{ bytes.Buffer }

func (w *fragmentWriter) Write(data []byte) (int, error) {
	return w.Buffer.Write(data[:min(2, len(data))])
}

func TestFrameRejectsInvalidSizesAndTruncation(t *testing.T) {
	for _, size := range []uint32{0, MaxFrameSize + 1, ^uint32(0)} {
		var frame bytes.Buffer
		_ = binary.Write(&frame, binary.LittleEndian, size)
		if _, err := ReadFrame(&frame); err == nil {
			t.Fatalf("accepted %d", size)
		}
	}
	var fragment fragmentWriter
	payload := []byte(`{"file":"/app/responses/response.json","result":null}`)
	if err := WriteFrame(&fragment, payload); err != nil {
		t.Fatal(err)
	}
	got, err := ReadFrame(&fragment)
	if err != nil || !bytes.Equal(got, payload) {
		t.Fatal("partial writes corrupted frame", err)
	}
	var truncated bytes.Buffer
	_ = binary.Write(&truncated, binary.LittleEndian, uint32(100))
	_, _ = truncated.Write([]byte("short"))
	if _, err := ReadFrame(&truncated); err != io.ErrUnexpectedEOF {
		t.Fatal(err)
	}
}
