package llm

import "encoding/json"

type Role string

const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

type ContentBlock struct {
	Type string `json:"type"`
	Text string `json:"text,omitempty"`

	ID     string          `json:"id,omitempty"`
	Name   string          `json:"name,omitempty"`
	Input  json.RawMessage `json:"input,omitempty"`

	ToolUseID string `json:"tool_use_id,omitempty"`
	Content   string `json:"content,omitempty"`
	IsError   bool   `json:"is_error,omitempty"`
}

type Message struct {
	Role    Role           `json:"role"`
	Content []ContentBlock `json:"content"`
}

type ToolSchema struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	InputSchema json.RawMessage `json:"input_schema"`
}

type ProviderRequest struct {
	Model     string       `json:"model"`
	System    string       `json:"system"`
	Messages  []Message    `json:"messages"`
	Tools     []ToolSchema `json:"tools"`
	MaxTokens uint32       `json:"max_tokens"`
}

type ToolCall struct {
	ID    string          `json:"id"`
	Name  string          `json:"name"`
	Input json.RawMessage `json:"input"`
}

type StreamEvent struct {
	Type       string   `json:"type"`
	Text       string   `json:"text,omitempty"`
	ID         string   `json:"id,omitempty"`
	Name       string   `json:"name,omitempty"`
	Call       *ToolCall `json:"call,omitempty"`
	StopReason string   `json:"stop_reason,omitempty"`
	Error      string   `json:"error,omitempty"`
}

type ToolResult struct {
	Content string `json:"content"`
	IsError bool   `json:"is_error"`
}
