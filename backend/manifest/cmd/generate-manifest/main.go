package main

import (
	"context"
	"flag"
	"log"
	"os"

	"epac/manifest"
)

func main() {
	bucket := flag.String("bucket", os.Getenv("ARTIFACTS_BUCKET"), "S3 bucket name (or set ARTIFACTS_BUCKET)")
	flag.Parse()

	if *bucket == "" {
		log.Fatal("bucket is required: set -bucket flag or ARTIFACTS_BUCKET env var")
	}

	log.Printf("generating manifest for s3://%s", *bucket)
	if err := manifest.Generate(context.Background(), *bucket); err != nil {
		log.Fatalf("generate manifest: %v", err)
	}
	log.Printf("manifest.json written to s3://%s/manifest.json", *bucket)
}
