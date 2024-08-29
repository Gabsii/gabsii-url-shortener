package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/gorilla/mux"
)

var redisClient *redis.Client
var hostURL string

func init() {
	hostURL = os.Getenv("HOST_URL")
	if hostURL == "" {
		hostURL = "http://localhost:8080"
	}

	// Initialize Redis client
	redisClient = redis.NewClient(&redis.Options{
		Addr: "redis:6379",
	})

	// Check Redis connection
	_, err := redisClient.Ping(context.Background()).Result()
	if err != nil {
		log.Fatalf("Could not connect to Redis: %v", err)
	}

	// Seed the random number generator once
	rand.Seed(time.Now().UnixNano())
}

func main() {
	// Initialize router
	r := mux.NewRouter()

	// Define routes
	r.HandleFunc("/shorten", shortenURL).Methods("POST")
	r.HandleFunc("/health-check", healthCheck).Methods("GET")
	r.HandleFunc("/", indexRoute).Methods("GET")
	r.HandleFunc("/{shortURL}", redirectURL).Methods("GET")

	// Start server
	log.Println("Server starting on port 8080...")
	log.Fatal(http.ListenAndServe(":8080", r))
}

func indexRoute(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, "pages/index.html")
}

func shortenURL(w http.ResponseWriter, r *http.Request) {
	longURL := r.FormValue("url")
	if longURL == "" {
		http.Error(w, "URL is required", http.StatusBadRequest)
		return
	}

	shortURL := generateShortURL()
	err := redisClient.Set(r.Context(), shortURL, longURL, 0).Err()
	log.Printf("Shortening URL: %s -> %s\n", shortURL, longURL)

	if err != nil {
		http.Error(w, "Error storing URL", http.StatusInternalServerError)
		return
	}

	// Get all the query parameters as a map
	queryParams := r.URL.Query()

	// Access a specific query parameter by key
	format := queryParams.Get("format") // This will return the first value associated with "paramKey"

	if format == "" {
		fmt.Fprintf(w, "%s/%s", hostURL, shortURL)
	} else if format == "html" {
		// Redirect to the index with the shortURL as a query parameter
		fullURL := fmt.Sprintf("%s/%s", hostURL, shortURL)
		redirectURL := fmt.Sprintf("/?shortURL=%s", fullURL)
		http.Redirect(w, r, redirectURL, http.StatusFound)
	}
}

func redirectURL(w http.ResponseWriter, r *http.Request) {
	shortURL := mux.Vars(r)["shortURL"]
	longURL, err := redisClient.Get(r.Context(), shortURL).Result()
	if err == redis.Nil {
		http.NotFound(w, r)
		return
	} else if err != nil {
		http.Error(w, "Error retrieving URL", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, longURL, http.StatusFound)
}

func healthCheck(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
}

func generateShortURL() string {
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	const length = 8
	shortURL := make([]byte, length)
	for i := range shortURL {
		shortURL[i] = charset[rand.Intn(len(charset))]
	}
	candidate := string(shortURL)

	if candidate == "shorten" {
		return generateShortURL()
	}

	return candidate
}
