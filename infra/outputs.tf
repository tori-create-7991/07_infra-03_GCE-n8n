output "workload_identity_provider" {
  description = "The Workload Identity Provider resource name"
  value       = google_iam_workload_identity_pool_provider.github_provider.name
}

output "service_account_email" {
  description = "The Service Account email"
  value       = google_service_account.github_actions.email
}

output "n8n_ip" {
  description = "The external IP address of the n8n instance"
  value       = google_compute_instance.n8n.network_interface[0].access_config[0].nat_ip
}
