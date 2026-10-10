variable "enable_tracing" {
  description = "Enable local OTLP collectors and sampled application tracing on ordinary tasks, never credential-maintenance terminals."
  type        = bool
  default     = true
}
variable "trace_sample_ratio" {
  description = "Application local trace sampling probability; incoming flags cannot override this ratio. X-Ray retains traces for its service-defined 30 days."
  type        = number
  default     = 0.1
  validation {
    condition     = var.trace_sample_ratio >= 0 && var.trace_sample_ratio <= 1
    error_message = "Trace sampling must be between 0 and 1."
  }
}
variable "tracing_collector_image" {
  description = "Immutable ADOT collector image, with linux/arm64 and linux/amd64 support. Default is the verified v0.50.0 multi-platform manifest."
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-otel-collector@sha256:7968fb60db6a2390a47ba6a2df029745638486e285c9b2487da1b722d0855a3e"
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.tracing_collector_image))
    error_message = "Pin the collector by immutable registry digest."
  }
}
locals {
  tracing_environment = {
    for role in ["backend", "launcher", "worker"] : role => var.enable_tracing ? {
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = "http://127.0.0.1:4318/v1/traces"
      OTEL_SERVICE_NAME                  = "dispatch-${role}"
      OTEL_TRACES_SAMPLER_ARG            = tostring(var.trace_sample_ratio)
    } : {}
  }
  # Loopback receiver: no ingress or credential-bearing remote OTLP endpoint.
  # No debug exporter, payload logging, SQL instrumentation or persistent queue.
  tracing_configuration = yamlencode({
    receivers = { otlp = { protocols = { http = { endpoint = "127.0.0.1:4318" } } } }
    processors = {
      memory_limiter = { check_interval = "1s", limit_mib = 128, spike_limit_mib = 32 }
      batch          = { timeout = "5s", send_batch_size = 256, send_batch_max_size = 512 }
    }
    exporters = { awsxray = { region = data.aws_region.current.region, indexed_attributes = ["service.name"] } }
    service = {
      telemetry = { logs = { level = "warn" } }
      pipelines = { traces = { receivers = ["otlp"], processors = ["memory_limiter", "batch"], exporters = ["awsxray"] } }
    }
  })
  tracing_containers = {
    for role in ["backend", "launcher", "worker"] : role => var.enable_tracing ? [{
      name                   = "tracing"
      image                  = var.tracing_collector_image
      essential              = false
      user                   = "65532:65532"
      readonlyRootFilesystem = true
      memory                 = 256
      memoryReservation      = 64
      cpu                    = 0
      command                = ["--config=env:AOT_CONFIG_CONTENT"]
      environment            = [{ name = "AOT_CONFIG_CONTENT", value = local.tracing_configuration }]
      linuxParameters        = { initProcessEnabled = true, capabilities = { add = [], drop = ["ALL"] } }
      portMappings           = []
      mountPoints            = []
      volumesFrom            = []
      stopTimeout            = 30
      logConfiguration = { logDriver = "awslogs", options = {
        awslogs-group         = aws_cloudwatch_log_group.this[role].name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "tracing"
      } }
    }] : []
  }
}
resource "aws_iam_role_policy" "tracing" {
  for_each = var.enable_tracing ? toset(["backend", "launcher", "worker"]) : toset([])
  role     = aws_iam_role.task[each.key].id
  # X-Ray's write APIs do not support resource-level permissions. No read,
  # sampling-control, logs-read or credential privileges are added.
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*"
  }] })
}
