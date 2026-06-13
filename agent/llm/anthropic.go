package llm

import "context"

type AnthropicProvider struct {
	APIKey string
}

func (p *AnthropicProvider) Stream(ctx context.Context, request ProviderRequest) (<-chan StreamEvent, error) {
	// TODO: implement Anthropic SSE streaming
	ch := make(chan StreamEvent)
	close(ch)
	return ch, nil
}
