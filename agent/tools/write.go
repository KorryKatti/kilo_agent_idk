package tools

import (
	"agent/llm"
	"context"
)

type WriteTool struct{}

func (WriteTool) Schema() llm.ToolSchema {
	return llm.ToolSchema{Name: "write", Description: "Write content to a file."}
}

func (WriteTool) Execute(ctx context.Context, input []byte) (llm.ToolResult, error) {
	// TODO: implement
	return llm.ToolResult{}, nil
}
