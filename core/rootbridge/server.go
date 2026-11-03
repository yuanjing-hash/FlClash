package rootbridge

import (
	"crypto/subtle"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net"
	"sync"
	"time"
)

const MaxFrameSize = 64 << 20

type Server struct {
	Token  string
	Invoke func([]byte, func([]byte))
	Events func(func([]byte))
	mu     sync.Mutex
	active net.Conn
}

func ReadFrame(r io.Reader) ([]byte, error) {
	var size uint32
	if err := binary.Read(r, binary.LittleEndian, &size); err != nil {
		return nil, err
	}
	if size == 0 || size > MaxFrameSize {
		return nil, errors.New("invalid root frame size")
	}
	data := make([]byte, size)
	_, err := io.ReadFull(r, data)
	return data, err
}

func WriteFrame(w io.Writer, data []byte) error {
	if len(data) == 0 || len(data) > MaxFrameSize {
		return errors.New("invalid root frame size")
	}
	header := make([]byte, 4)
	binary.LittleEndian.PutUint32(header, uint32(len(data)))
	for _, part := range [][]byte{header, data} {
		for len(part) > 0 {
			n, err := w.Write(part)
			if err != nil {
				return err
			}
			if n == 0 {
				return io.ErrShortWrite
			}
			part = part[n:]
		}
	}
	return nil
}

func (s *Server) Serve(listener net.Listener) error {
	for {
		conn, err := listener.Accept()
		if err != nil {
			return err
		}
		go s.serve(conn)
	}
}

func (s *Server) serve(conn net.Conn) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	var size uint32
	if binary.Read(conn, binary.LittleEndian, &size) != nil || size == 0 || size > 4096 {
		return
	}
	data := make([]byte, size)
	if _, err := io.ReadFull(conn, data); err != nil {
		return
	}
	var hello struct {
		Token string `json:"token"`
	}
	if json.Unmarshal(data, &hello) != nil || len(s.Token) < 32 || subtle.ConstantTimeCompare([]byte(hello.Token), []byte(s.Token)) != 1 {
		return
	}
	_ = conn.SetDeadline(time.Time{})
	var writeMu sync.Mutex
	send := func(data []byte) {
		writeMu.Lock()
		defer writeMu.Unlock()
		_ = conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
		if WriteFrame(conn, data) != nil {
			_ = conn.Close()
		}
	}
	s.mu.Lock()
	if s.active != nil {
		_ = s.active.Close()
	}
	s.active = conn
	send([]byte(`{"ready":true}`))
	s.Events(send)
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.active == conn {
			s.active = nil
			s.Events(nil)
		}
	}()
	for {
		data, err := ReadFrame(conn)
		if err != nil {
			return
		}
		// Dispatch on the reader: Core stamps latest-intent sequence numbers here,
		// then runs handlers concurrently, as it does for JNI and desktop IPC.
		s.Invoke(data, send)
	}
}
