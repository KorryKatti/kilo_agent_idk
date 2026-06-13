package tools

import (
	"agent/llm"
	"context"
)

type BashTool struct{}

func (BashTool) Schema() llm.ToolSchema {
	return llm.ToolSchema{Name: "bash", Description: "Execute a shell command."}
}

func (BashTool) Execute(ctx context.Context, input []byte) (llm.ToolResult, error) {
	// TODO: implement
	return llm.ToolResult{}, nil
}
