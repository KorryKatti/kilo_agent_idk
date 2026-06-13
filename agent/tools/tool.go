package tools

import (
	"agent/llm"
	"context"
)

type Tool interface {
	Schema() llm.ToolSchema
	Execute(ctx context.Context, input []byte) (llm.ToolResult, error)
}
