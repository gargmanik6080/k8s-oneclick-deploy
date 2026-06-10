# Multi-stage build -> tiny distroless runtime image.
# Cross-compiles to the target platform (set automatically by BuildKit/buildx).
FROM --platform=$BUILDPLATFORM golang:1.26 AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/hello-world .

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/hello-world /hello-world
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/hello-world"]
