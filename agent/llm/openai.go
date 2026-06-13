package llm

import "context"

type OpenAIProvider struct {
	APIKey string
	BaseURL string
}

func (p *OpenAIProvider) Stream(ctx context.Context, request ProviderRequest) (<-chan StreamEvent, error) {
	// TODO: implement OpenAI Chat Completions SSE streaming
	ch := make(chan StreamEvent)
	close(ch)
	return ch, nil
}
