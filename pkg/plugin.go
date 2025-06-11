package pkg

import (
	"context"
	"fmt"

	"github.com/chainloop-dev/chainloop/app/cli/plugins"
)

// ExamplePlugin implements the Plugin interface
type ExamplePlugin struct{}

// Exec executes a command
func (p *ExamplePlugin) Exec(ctx context.Context, command string, arguments map[string]interface{}) (plugins.ExecResult, error) {
	switch command {
	case "example-chainloop-plugin":
		return p.execHello(ctx, arguments)
	default:
		return &Result{
			Error:    fmt.Sprintf("Unknown command: %s", command),
			ExitCode: 1,
		}, nil
	}
}

func (p *ExamplePlugin) execHello(_ context.Context, _ map[string]interface{}) (plugins.ExecResult, error) {
	return &Result{
		Output: "Hello, World!",
	}, nil
}

// GetMetadata returns plugin metadata
func (p *ExamplePlugin) GetMetadata(ctx context.Context) (plugins.PluginMetadata, error) {
	return plugins.PluginMetadata{
		Name:        "example-chainloop-plugin",
		Version:     "1.0.0",
		Description: "GitHub example CLI plugin",
		Commands: []plugins.CommandInfo{
			{
				Name:        "example-chainloop-plugin",
				Description: "Greet with hello",
				Usage:       "chainloop example-chainloop-plugin",
				Flags:       []plugins.FlagInfo{},
			},
		},
	}, nil
}

// Result implements the ExecResult interface
type Result struct {
	Output   string
	Error    string
	ExitCode int
	Data     map[string]interface{}
}

func (r *Result) GetOutput() string {
	return r.Output
}

func (r *Result) GetError() string {
	return r.Error
}

func (r *Result) GetExitCode() int {
	return r.ExitCode
}

func (r *Result) GetData() map[string]interface{} {
	return r.Data
}
