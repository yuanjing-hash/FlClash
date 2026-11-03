//go:build !(darwin || linux)

package core

func initOwnership(homeDir string) {}

func scheduleReclaimOwnership() {}

func reclaimDirOwnership(path string) {}
