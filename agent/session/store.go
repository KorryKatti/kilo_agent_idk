package session

type Event struct {
	Type string `json:"type"`
}

type Store struct {
	events []Event
}

func New() *Store {
	return &Store{}
}

func (s *Store) Append(event Event) {
	s.events = append(s.events, event)
}
