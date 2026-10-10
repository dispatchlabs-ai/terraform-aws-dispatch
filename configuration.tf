# Dispatch owns these configuration schemas and all runtime lifecycle operations.
# Only public configuration and secret REFERENCES are rendered here. ECS supplies
# secret values; dispatch-bootstrap materializes restricted files before exec.
locals {
  bootstrap_directory    = "/tmp/dispatch-bootstrap"
  configured_apps        = var.application == null ? [] : [var.application]
  backend_dns_name       = "backend.${aws_service_discovery_private_dns_namespace.this.name}"
  generated_launcher_url = var.launcher_internal_alb ? "http://${aws_lb.launcher[0].dns_name}:8830" : "http://launcher.${aws_service_discovery_private_dns_namespace.this.name}:8830"
  generated_callback_url = local.backend_callback_enabled ? "https://${local.backend_callback_hostname}" : "https://${local.backend_dns_name}:3001"

  # JSON files refer only to restricted paths, not credential-bearing URLs/keys.
  store_configuration = [for app in local.configured_apps : {
    for store in ["auth", "provider", "catalog", "routing", "directory"] : "${store}.json" => jsonencode(merge({
      databaseUrlFile                     = "${local.bootstrap_directory}/${store}-db-url"
      databaseCaFile                      = "${local.bootstrap_directory}/database-ca.pem"
      }, store == "directory" ? { storeId = "${app.installation_id}:directory" } : { installationId = app.installation_id }, contains(["auth", "provider", "catalog"], store) ? {
      encryptionKeyFile                   = "${local.bootstrap_directory}/${store}-key"
    } : {}))
  }]

  role_public_files = [for app in local.configured_apps : {
    backend = merge(local.store_configuration[0], {
      "database-ca.pem"  = app.database_ca_pem
      "backend-ca.pem"   = app.backend_ca_pem
      "backend-cert.pem" = app.backend_certificate_pem
      "backend.json" = jsonencode({
        installationId           = app.installation_id
        configurationRevision    = app.configuration_revision
        authStoreConfigFile      = "${local.bootstrap_directory}/auth.json"
        providerStoreConfigFile  = "${local.bootstrap_directory}/provider.json"
        mcpStoreConfigFile       = "${local.bootstrap_directory}/catalog.json"
        routingStoreConfigFile   = "${local.bootstrap_directory}/routing.json"
        directoryStoreConfigFile = "${local.bootstrap_directory}/directory.json"
        postgresStores           = { adminUrlFile = "${local.bootstrap_directory}/workers-db-url", caFile = "${local.bootstrap_directory}/database-ca.pem" }
        tls                      = { keyFile = "${local.bootstrap_directory}/backend-key.pem", certFile = "${local.bootstrap_directory}/backend-cert.pem" }
        artifacts = {
          endpoint = "https://s3.${data.aws_region.current.region}.amazonaws.com"
          region   = data.aws_region.current.region, bucket = aws_s3_bucket.artifacts.id, prefix = "artifacts", taskRole = true
        }
        workerKeyFile     = "${local.bootstrap_directory}/worker-token"
        launcherTokenFile = "${local.bootstrap_directory}/launcher-token"
        operatorTokenFile = "${local.bootstrap_directory}/operator-token"
        launcherUrl       = local.generated_launcher_url
      })
      }, lookup(var.service_deployment_mode, "backend", "stop-first") == "rolling" ? {
      "controller.json" = jsonencode({
        databaseConfigFile = "${local.bootstrap_directory}/routing.json"
        tokenFile          = "${local.bootstrap_directory}/backend-peer-token"
        host               = "0.0.0.0", port = 3001
        tls                = { keyFile = "${local.bootstrap_directory}/backend-key.pem", certFile = "${local.bootstrap_directory}/backend-cert.pem" }
        peerTls            = { caFile = "${local.bootstrap_directory}/backend-ca.pem", serverName = local.backend_dns_name }
      })
    } : {})
    launcher = merge({
      "database-ca.pem" = app.database_ca_pem
      "backend-ca.pem"  = app.backend_ca_pem
      "launcher.json" = jsonencode({
        installationId = app.installation_id
        postgres       = { urlFile = "${local.bootstrap_directory}/launcher-db-url", caFile = "${local.bootstrap_directory}/database-ca.pem" }
        tokenFile      = "${local.bootstrap_directory}/launcher-token"
        workerKeyFile  = "${local.bootstrap_directory}/worker-token"
        backendCaFile  = "${local.bootstrap_directory}/backend-ca.pem"
        host           = "0.0.0.0", port = 8830, driverType = "ecs"
        driver = {
          region                = data.aws_region.current.region
          cluster               = aws_ecs_cluster.workers.arn
          taskDefinition        = try(aws_ecs_task_definition.worker[0].arn, null)
          containerName         = "worker"
          subnets               = aws_subnet.private[*].id
          securityGroups        = [aws_security_group.tasks["worker"].id]
          configurationRevision = app.configuration_revision
          platformVersion       = "1.4.0"
          environment           = { DISPATCH_BACKEND_INTERNAL_URL = local.generated_callback_url }
        }
      })
      }, lookup(var.service_deployment_mode, "launcher", "stop-first") == "rolling" ? {
      "controller-database.json" = jsonencode({
        installationId  = app.installation_id
        databaseUrlFile = "${local.bootstrap_directory}/launcher-db-url"
        databaseCaFile  = "${local.bootstrap_directory}/database-ca.pem"
      })
      "controller.json" = jsonencode({
        databaseConfigFile = "${local.bootstrap_directory}/controller-database.json"
        tokenFile          = "${local.bootstrap_directory}/launcher-peer-token"
        host               = "0.0.0.0", port = 8830
      })
    } : {})
    initializer = {
      "database-ca.pem" = app.database_ca_pem
      "database-init.json" = jsonencode({
        installationId  = app.installation_id
        host            = aws_db_instance.this.address, port = 5432
        adminSecretFile = "${local.bootstrap_directory}/rds-master.json"
        caFile          = "${local.bootstrap_directory}/database-ca.pem"
        stores          = { for store in keys(app.database_url_secret_arns) : store => "${local.bootstrap_directory}/${store}-db-url" }
      })
    }
    maintenance = merge({ for filename, content in local.store_configuration[0] : filename => content if contains(["auth.json", "provider.json"], filename) }, {
      "database-ca.pem" = app.database_ca_pem
    })
  }]

  role_secret_files = [for app in local.configured_apps : {
    backend = merge(
      { for store, arn in app.database_url_secret_arns : "${store}-db-url" => { arn = arn, encoding = "utf8" } if store != "launcher" },
      { for store, arn in app.encryption_key_secret_arns : "${store}-key" => { arn = arn, encoding = "base64" } },
      { for name in ["worker", "launcher", "operator"] : "${name}-token" => { arn = app.token_secret_arns[name], encoding = "utf8" } },
      { "backend-key.pem" = { arn = app.backend_private_key_secret_arn, encoding = "utf8" } },
      lookup(var.service_deployment_mode, "backend", "stop-first") == "rolling" ? { "backend-peer-token" = { arn = app.token_secret_arns.backend_peer, encoding = "utf8" } } : {}
    )
    launcher = merge({
      "launcher-db-url" = { arn = app.database_url_secret_arns.launcher, encoding = "utf8" }
      "launcher-token"  = { arn = app.token_secret_arns.launcher, encoding = "utf8" }
      "worker-token"    = { arn = app.token_secret_arns.worker, encoding = "utf8" }
    }, lookup(var.service_deployment_mode, "launcher", "stop-first") == "rolling" ? { "launcher-peer-token" = { arn = app.token_secret_arns.launcher_peer, encoding = "utf8" } } : {})
    initializer = merge({ for store, arn in app.database_url_secret_arns : "${store}-db-url" => { arn = arn, encoding = "utf8" } }, {
      "rds-master.json" = { arn = aws_db_instance.this.master_user_secret[0].secret_arn, encoding = "utf8" }
    })
    maintenance = merge(
      { for store in ["auth", "provider"] : "${store}-db-url" => { arn = app.database_url_secret_arns[store], encoding = "utf8" } },
      { for store in ["auth", "provider"] : "${store}-key" => { arn = app.encryption_key_secret_arns[store], encoding = "base64" } }
    )
  }]

  role_environment = [for app in local.configured_apps : {
    for role in ["backend", "launcher", "initializer", "maintenance"] : role => merge({
      DISPATCH_ORIGIN        = app.origin
      DISPATCH_COMPANY_ID    = app.company_id
      DISPATCH_COMPANY_NAME  = app.company_name
      DISPATCH_HOST          = "0.0.0.0"
      DISPATCH_PORT          = "3001"
      DISPATCH_DATA_DIR      = "/data"
      DISPATCH_WORKSPACE_DIR = "/workspace"
      }, role == "backend" ? { DISPATCH_BACKEND_WORKERS_CONFIG_FILE = "${local.bootstrap_directory}/backend.json" } : {},
      role == "launcher" ? { DISPATCH_LAUNCHER_CONFIG_FILE = "${local.bootstrap_directory}/launcher.json" } : {},
      contains(["backend", "launcher"], role) && lookup(var.service_deployment_mode, role, "stop-first") == "rolling" ? {
        DISPATCH_CONTROLLER_CONFIG_FILE = "${local.bootstrap_directory}/controller.json"
    } : {})
  }]

  # Stable naming from fixed filenames keeps environment and secret sources disjoint.
  generated_bundles = [for app in local.configured_apps : {
    for role in ["backend", "launcher", "initializer", "maintenance"] : role => {
      environment = merge(local.role_environment[0][role], {
        for filename, content in local.role_public_files[0][role] : "DISPATCH_FILE_${upper(replace(filename, "/[^A-Za-z0-9]/", "_"))}" => content
        }, {
        DISPATCH_BOOTSTRAP_FILES = jsonencode(merge(
          { for filename, content in local.role_public_files[0][role] : filename => { env = "DISPATCH_FILE_${upper(replace(filename, "/[^A-Za-z0-9]/", "_"))}", encoding = "utf8" } },
          { for filename, secret in local.role_secret_files[0][role] : filename => { env = "DISPATCH_SECRET_${upper(replace(filename, "/[^A-Za-z0-9]/", "_"))}", encoding = secret.encoding } }
        ))
      })
      secrets = { for filename, secret in local.role_secret_files[0][role] : "DISPATCH_SECRET_${upper(replace(filename, "/[^A-Za-z0-9]/", "_"))}" => secret.arn }
    }
  }]

  generated_services = { for role in ["backend", "launcher"] : role => {
    environment = var.application == null ? tomap({}) : tomap(local.generated_bundles[0][role].environment)
    secrets     = var.application == null ? tomap({}) : tomap(local.generated_bundles[0][role].secrets)
  } }
  generated_database_initializer = var.enable_database_initializer && var.application != null ? merge(local.generated_bundles[0].initializer, {
    command = ["dispatch-bootstrap", "database-init", "--config", "${local.bootstrap_directory}/database-init.json", "--verify"]
  }) : null
  generated_credential_maintenance = var.enable_credential_maintenance && var.application != null ? local.generated_bundles[0].maintenance : null
}
