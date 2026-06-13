package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "OK")
	})

	log.Println("agent listening on :3000")
	log.Fatal(http.ListenAndServe(":3000", nil))
}
