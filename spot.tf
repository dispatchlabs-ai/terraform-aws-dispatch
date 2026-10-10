variable "worker_capacity_provider" {
  description = "Worker capacity only. Spot is opt-in; interruptions require confirmed termination and explicit application recovery. Controllers remain On-Demand."
  type        = string
  default     = "FARGATE"
  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.worker_capacity_provider)
    error_message = "Select FARGATE or FARGATE_SPOT."
  }
}
resource "aws_ecs_cluster_capacity_providers" "workers" {
  cluster_name       = aws_ecs_cluster.workers.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}
