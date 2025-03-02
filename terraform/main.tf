resource "kind_cluster" "jenkins_postgres" {
  name            = "jenkins-postgres-cluster"
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      
      extra_port_mappings {
        container_port = 30000
        host_port      = 30000
      }
      extra_port_mappings {
        container_port = 30001
        host_port      = 30001
      }
      extra_port_mappings {
        container_port = 30002
        host_port      = 30002
      }
    }

    node {
      role = "worker"
    }

    node {
      role = "worker"
    }
  }
}

resource "null_resource" "configure_storage" {
  depends_on = [kind_cluster.jenkins_postgres]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
      kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    EOT
  }
}