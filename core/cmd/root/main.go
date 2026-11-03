//go:build android

package main

import (
	"core"
	"flag"
	"fmt"
	"os"
)

func main() {
	launch := flag.String("root-config", "", "Private FlClash root launch configuration")
	check := flag.Bool("check", false, "Validate the UI configuration without starting listeners")
	flag.Parse()
	if err := core.RunRoot(*launch, *check); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
