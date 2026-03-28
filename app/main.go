package main

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type app struct {
	s3Client   *s3.Client
	bucketName string
}

func main() {
	ctx := context.Background()

	bucket := os.Getenv("BUCKET_NAME")
	if bucket == "" {
		log.Fatal("BUCKET_NAME must be set")
	}

	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("failed to load AWS config: %v", err)
	}

	a := &app{
		s3Client:   s3.NewFromConfig(cfg),
		bucketName: bucket,
	}

	lambda.Start(a.handler)
}

func (a *app) handler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if strings.ToUpper(req.RequestContext.HTTP.Method) != http.MethodGet {
		return jsonError(http.StatusMethodNotAllowed, "method not allowed"), nil
	}

	key := strings.TrimSpace(req.QueryStringParameters["key"])
	if key == "" {
		return jsonError(http.StatusBadRequest, "missing required query parameter: key"), nil
	}

	// Basic hardening against odd paths. S3 object keys can legally contain many chars,
	// but for a challenge like this it's reasonable to normalize obvious path traversal shapes.
	key = strings.TrimPrefix(path.Clean("/"+key), "/")
	if key == "." || key == "" {
		return jsonError(http.StatusBadRequest, "invalid key"), nil
	}

	out, err := a.s3Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: &a.bucketName,
		Key:    &key,
	})
	if err != nil {
		log.Printf("GetObject failed for key=%q: %v", key, err)
		return mapS3Error(err), nil
	}
	defer out.Body.Close()

	body, err := io.ReadAll(out.Body)
	if err != nil {
		log.Printf("failed reading S3 object body: %v", err)
		return jsonError(http.StatusInternalServerError, "failed to read object"), nil
	}

	headers := map[string]string{
		"Content-Type":                valueOrDefault(out.ContentType, detectContentType(body)),
		"Cache-Control":               valueOrDefault(out.CacheControl, "public, max-age=60"),
		"X-Content-Type-Options":      "nosniff",
		"Content-Security-Policy":     "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
		"Referrer-Policy":             "no-referrer",
		"Strict-Transport-Security":   "max-age=63072000; includeSubDomains; preload",
		"X-Frame-Options":             "DENY",
	}

	if out.ETag != nil && *out.ETag != "" {
		headers["ETag"] = *out.ETag
	}
	if out.ContentDisposition != nil && *out.ContentDisposition != "" {
		headers["Content-Disposition"] = *out.ContentDisposition
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode:      http.StatusOK,
		Headers:         headers,
		Body:            base64.StdEncoding.EncodeToString(body),
		IsBase64Encoded: true,
	}, nil
}

func mapS3Error(err error) events.APIGatewayV2HTTPResponse {
	msg := err.Error()

	switch {
	case strings.Contains(msg, "NoSuchKey"), strings.Contains(strings.ToLower(msg), "not found"):
		return jsonError(http.StatusNotFound, "object not found")
	case strings.Contains(msg, "AccessDenied"):
		return jsonError(http.StatusForbidden, "access denied")
	default:
		return jsonError(http.StatusInternalServerError, "failed to retrieve object")
	}
}

func jsonError(status int, message string) events.APIGatewayV2HTTPResponse {
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: fmt.Sprintf(`{"error":%q}`, message),
	}
}

func valueOrDefault(v *string, fallback string) string {
	if v == nil || strings.TrimSpace(*v) == "" {
		return fallback
	}
	return *v
}

func detectContentType(b []byte) string {
	if len(b) == 0 {
		return "application/octet-stream"
	}
	return http.DetectContentType(b)
}

// Prevent unused import complaints if you later switch to structured AWS errors.
var _ = errors.New