provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Data Disk (20GB) ---
# This disk persists independently of the VM instance.
resource "google_compute_disk" "n8n_data" {
  name  = "n8n-data-disk"
  type  = "pd-standard"
  zone  = var.zone
  size  = 20
}

# --- VM Instance (e2-micro, 10GB Boot) ---
resource "google_compute_instance" "n8n" {
  name         = "n8n-server"
  machine_type = "e2-micro"
  zone         = var.zone

  # Free Tier: e2-micro is free in us-central1, us-east1, us-west1 (as of knowledge cutoff)
  # Standard Persistent Disk is free up to 30GB total.

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
      type  = "pd-standard"
    }
  }

  attached_disk {
    source      = google_compute_disk.n8n_data.id
    device_name = "n8n_data_disk" # Can be used to identify in guest, but /dev/disk/by-id/google-* is safer or simple /dev/sdb
  }

  network_interface {
    network = "default"
    access_config {
      # Ephemeral IP
    }
  }

  metadata_startup_script = file("${path.module}/startup_script.sh")

  tags = ["n8n-server"]

  # Allow stopping for updates
  allow_stopping_for_update = true

  service_account {
    # Compute Engine default service account or a custom one.
    # Using default for simplicity, but scope limited.
    scopes = ["cloud-platform"]
  }
}

# --- Firewall ---
resource "google_compute_firewall" "n8n" {
  name    = "allow-n8n-5678"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["5678"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["n8n-server"]
}
