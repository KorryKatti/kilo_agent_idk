package tools

import (
	"agent/llm"
	"context"
)

type EditTool struct{}

func (EditTool) Schema() llm.ToolSchema {
	return llm.ToolSchema{Name: "edit", Description: "Edit a file using text replacement."}
}

func (EditTool) Execute(ctx context.Context, input []byte) (llm.ToolResult, error) {
	// TODO: implement
	return llm.ToolResult{}, nil
}
