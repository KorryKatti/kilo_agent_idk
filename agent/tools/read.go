package tools

import (
	"agent/llm"
	"context"
)

type ReadTool struct{}

func (ReadTool) Schema() llm.ToolSchema {
	return llm.ToolSchema{Name: "read", Description: "Read a file."}
}

func (ReadTool) Execute(ctx context.Context, input []byte) (llm.ToolResult, error) {
	// TODO: implement
	return llm.ToolResult{}, nil
}
