terraform {
  backend "gcs" {
    bucket  = "n8n-tf-state-tori-dev-n8n"
    prefix  = "terraform/state"
  }
}
