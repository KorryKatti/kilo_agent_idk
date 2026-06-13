package llm

import "context"

type Provider interface {
	Stream(ctx context.Context, request ProviderRequest) (<-chan StreamEvent, error)
}
