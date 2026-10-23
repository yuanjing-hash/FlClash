package main

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func controller(path, secret string) ([]byte, error) {
	client := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{Proxy: nil}}
	req, err := http.NewRequest(http.MethodGet, "http://127.0.0.1:19090"+path, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+secret)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("controller status %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 4<<20))
}

func dns(network string) error {
	conn, err := net.DialTimeout(network, "203.0.113.53:53", 5*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()
	if err = conn.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return err
	}
	query := []byte{0x42, 0x19, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0}
	for _, label := range strings.Split("root-tun-b.example.com", ".") {
		query = append(query, byte(len(label)))
		query = append(query, label...)
	}
	query = append(query, 0, 0, 1, 0, 1)
	wire := query
	if network == "tcp" {
		wire = append([]byte{byte(len(query) >> 8), byte(len(query))}, query...)
	}
	if _, err = conn.Write(wire); err != nil {
		return err
	}
	answer := make([]byte, 4096)
	var size int
	if network == "tcp" {
		var length [2]byte
		if _, err = io.ReadFull(conn, length[:]); err != nil {
			return err
		}
		size = int(binary.BigEndian.Uint16(length[:]))
		if size > len(answer) {
			return fmt.Errorf("oversized DNS response: %d", size)
		}
		_, err = io.ReadFull(conn, answer[:size])
	} else {
		size, err = conn.Read(answer)
	}
	if err != nil {
		return err
	}
	if size < len(query)+16 || binary.BigEndian.Uint16(answer[:2]) != 0x4219 || answer[2]&0x80 == 0 || answer[3]&15 != 0 || binary.BigEndian.Uint16(answer[6:8]) != 1 {
		return fmt.Errorf("invalid DNS response: %x", answer[:size])
	}
	if string(answer[12:len(query)]) != string(query[12:]) {
		return fmt.Errorf("DNS question mismatch")
	}
	rr := answer[len(query):size]
	if len(rr) != 16 || rr[0] != 0xc0 || rr[1] != 12 || binary.BigEndian.Uint16(rr[2:4]) != 1 || binary.BigEndian.Uint16(rr[10:12]) != 4 || rr[12] != 198 || rr[13] != 18 {
		return fmt.Errorf("expected compressed fake-ip A record, got %x", rr)
	}
	fmt.Printf("DNS %s 203.0.113.53:53 -> %s (fake-ip; TEST-NET address has no DNS server)\n", network, net.IP(rr[12:16]))
	return nil
}

func traffic(ip, host, secret string) error {
	conn, err := net.DialTimeout("tcp4", net.JoinHostPort(ip, "80"), 10*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()
	if err = conn.SetDeadline(time.Now().Add(15 * time.Second)); err != nil {
		return err
	}
	port := strconv.Itoa(conn.LocalAddr().(*net.TCPAddr).Port)
	if _, err = fmt.Fprintf(conn, "GET / HTTP/1.1\r\nHost: %s\r\n", host); err != nil {
		return err
	}
	seen := false
	for attempt := 0; attempt < 20; attempt++ {
		body, apiErr := controller("/connections", secret)
		if apiErr != nil {
			return apiErr
		}
		var connections struct {
			Connections []struct {
				Metadata struct {
					Type            string `json:"type"`
					SourcePort      string `json:"sourcePort"`
					DestinationIP   string `json:"destinationIP"`
					DestinationPort string `json:"destinationPort"`
				} `json:"metadata"`
			} `json:"connections"`
		}
		if err = json.Unmarshal(body, &connections); err != nil {
			return err
		}
		for _, connection := range connections.Connections {
			m := connection.Metadata
			if strings.EqualFold(m.Type, "TUN") && m.SourcePort == port && m.DestinationIP == ip && m.DestinationPort == "80" {
				fmt.Printf("controller TUN evidence: %s\n", body)
				seen = true
				break
			}
		}
		if seen {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if !seen {
		return fmt.Errorf("probe source port %s absent from TUN /connections", port)
	}
	if _, err = io.WriteString(conn, "Connection: close\r\n\r\n"); err != nil {
		return err
	}
	resp, err := http.ReadResponse(bufio.NewReader(conn), &http.Request{Method: http.MethodGet})
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	n, err := io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	fmt.Printf("HTTP via TUN uid=%d: %s, body=%d bytes\n", os.Getuid(), resp.Status, n)
	if resp.StatusCode < 200 || resp.StatusCode >= 400 {
		return fmt.Errorf("unexpected HTTP status: %s", resp.Status)
	}
	return nil
}

func run(args []string) error {
	if len(args) > 0 && args[0] == "--shell" {
		if os.Getuid() != 0 {
			return fmt.Errorf("--shell requires root before dropping privileges")
		}
		if err := syscall.Setgroups([]int{3003}); err != nil {
			return err
		}
		if err := syscall.Setgid(2000); err != nil {
			return err
		}
		if err := syscall.Setuid(2000); err != nil {
			return err
		}
		args = args[1:]
		fmt.Printf("probe uid=%d gid=%d\n", os.Getuid(), os.Getgid())
	}
	if len(args) == 2 && args[0] == "dns" && (args[1] == "udp" || args[1] == "tcp") {
		return dns(args[1])
	}
	if len(args) == 4 && args[0] == "traffic" && net.ParseIP(args[1]).To4() != nil && !strings.ContainsAny(args[2], "\r\n") {
		return traffic(args[1], args[2], args[3])
	}
	if len(args) == 2 && args[0] == "health" {
		body, err := controller("/version", args[1])
		fmt.Printf("%s\n", body)
		return err
	}
	return fmt.Errorf("usage: probe [--shell] dns udp|tcp / traffic IPv4 host secret / health secret")
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
