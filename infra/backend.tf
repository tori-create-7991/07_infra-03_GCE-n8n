terraform {
  backend "gcs" {
    # bucket is passed via -backend-config="bucket=<name>"
    prefix = "terraform/state"
  }
}
