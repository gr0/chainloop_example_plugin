package main

import (
	"log"
	"os"

	"github.com/chainloop-dev/chainloop/app/cli/plugins"
	"github.com/gr0/chainloop_example_plugin/pkg"
	"github.com/hashicorp/go-plugin"
)

func main() {
	log.SetOutput(os.Stderr)
	log.Println("Plugin starting...")

	// Create the plugin instance
	pluginInstance := &pkg.ExamplePlugin{}
	log.Println("Plugin instance created")

	// Serve the plugin
	plugin.Serve(&plugin.ServeConfig{
		HandshakeConfig: plugins.Handshake,
		Plugins: map[string]plugin.Plugin{
			"chainloop": &plugins.ChainloopCliPlugin{Impl: pluginInstance},
		},
	})
}
