FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/xiaote-backend ./cmd/server

FROM alpine:3.22
RUN apk add --no-cache ca-certificates && addgroup -S app && adduser -S -G app app \
    && mkdir /data && chown app:app /data
WORKDIR /app
COPY --from=build /out/xiaote-backend /usr/local/bin/xiaote-backend
USER app
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/xiaote-backend"]
