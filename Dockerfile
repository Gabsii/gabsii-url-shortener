FROM golang:1.18-alpine

WORKDIR /app

# Copy go.mod and main.go
COPY go.mod main.go ./

# Download dependencies and generate go.sum
RUN go mod download
RUN go mod tidy

# Build the application
RUN go build -o main .

EXPOSE 8080

CMD ["./main"]
