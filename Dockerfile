
FROM golang:1.23 AS builder

WORKDIR /src

COPY app/go.mod app/go.sum ./
RUN go mod download

COPY app/ ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o bootstrap ./main.go

# FROM public.ecr.aws/lambda/provided:al2023

# WORKDIR /var/task
# COPY --from=builder /src/bootstrap ./bootstrap

# CMD ["bootstrap"]

FROM public.ecr.aws/lambda/go:1.23

WORKDIR /var/task
COPY --from=builder /src/bootstrap ./bootstrap
CMD ["bootstrap"]