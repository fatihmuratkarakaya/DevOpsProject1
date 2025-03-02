output "cluster_name" {
  description = "Name of the created KIND cluster"
  value       = kind_cluster.jenkins_postgres.name
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = "~/.kube/config"
}