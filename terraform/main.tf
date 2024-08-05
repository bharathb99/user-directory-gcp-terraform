#create a VPC for the project
resource "google_compute_network" "vpc_name" {
  for_each = {
    for index, name in var.vpc_name : name => index
  }
  name = each.key
  auto_create_subnetworks = false
  routing_mode = var.routing_mode
  delete_default_routes_on_create = true
}

#create a "webapp" subnet for the VPC
resource "google_compute_subnetwork" "webapp" {
  for_each = google_compute_network.vpc_name
  name          = "${each.key}-webapp"
  ip_cidr_range = var.webapp_subnet_cidr
  region        = var.region
  network       = each.value.self_link
}

#create a "db" subnet for the VPC
resource "google_compute_subnetwork" "db" {
  for_each = google_compute_network.vpc_name
  name          = "${each.key}-db"
  ip_cidr_range = var.db_subnet_cidr
  region        = var.region
  network       = each.value.self_link
}

#defining routes
resource "google_compute_route" "webapp_route" {
    for_each = google_compute_network.vpc_name
    name                  = "${each.key}-webapp-route"
    network               = each.value.self_link
    dest_range            = "0.0.0.0/0"
    next_hop_gateway      = "default-internet-gateway"
}


# Firewall rule to allow traffic to the application port and deny SSH
resource "google_compute_firewall" "allow_application_traffic" {
  for_each = google_compute_network.vpc_name
  name    = "${each.key}-allow-application-traffic"
  network = each.value.self_link

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "deny_ssh" {
 for_each = google_compute_network.vpc_name
 name    = "${each.key}-deny-ssh"
 network = each.value.self_link

 deny {
   protocol = "tcp"
   ports    = ["22"]
 }

 source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_global_address" "private_ip_block" {
  for_each = toset(var.vpc_name)
  name         = "private-ip-block"
  purpose      = "VPC_PEERING"
  address_type = "INTERNAL"
  ip_version   = "IPV4"
  prefix_length = 16
  network       = google_compute_network.vpc_name[each.value].self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  for_each = toset(var.vpc_name)
  network       = google_compute_network.vpc_name[each.value].self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_block[each.value].name]
}

resource "google_sql_database_instance" "mysql_instance" {
  for_each      = google_compute_network.vpc_name
  name          = "mysql-instance-${each.key}"
  database_version = "MYSQL_8_0"
  region = var.region
  deletion_protection = false
  encryption_key_name = google_kms_crypto_key.cloudsql_encryption_key.id
  

  settings {
    tier = "db-f1-micro"
    availability_type = "REGIONAL"
    disk_type         = var.db_disk_type
    disk_size         = var.db_disk_size

    ip_configuration {
      ipv4_enabled  = false
      private_network = google_compute_network.vpc_name[each.key].self_link
    }


    backup_configuration{
      binary_log_enabled = true
      enabled = true
    }

}
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "mysql_database" {
  for_each = google_compute_network.vpc_name
  name = var.sql_database_name
  instance = google_sql_database_instance.mysql_instance[each.key].name
}

resource "google_sql_user" "user" {
  for_each = google_compute_network.vpc_name
  name = "webapp-${each.key}"
  instance = google_sql_database_instance.mysql_instance[each.key].name
  password = random_password.password.result
}

resource "random_password" "password" {
  length           = 10
  special          = false
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_compute_instance_template" "webapp_template" {
  name_prefix   = "webapp-instance-template-"
  machine_type  = var.machine_type

  disk {
    source_image = var.custom_image
    auto_delete  = true
    boot         = true
    disk_size_gb = 100  // Correctly specifying the disk size here
    disk_type    = "pd-balanced"


  }

  

  network_interface {
    network = google_compute_network.vpc_name[var.vpc_name[0]].self_link
    subnetwork = google_compute_subnetwork.webapp[var.vpc_name[0]].self_link

    access_config {}
  }

  service_account {
    email  = google_service_account.webapp_service_acc.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    export DB_HOST="${google_sql_database_instance.mysql_instance[var.vpc_name[0]].private_ip_address}"
    export DB_USER="${google_sql_user.user[var.vpc_name[0]].name}"
    export DB_PASS="${random_password.password.result}"
    export DB_NAME="Users"
    
    echo "SQLALCHEMY_DATABASE_URI=mysql+pymysql://$${DB_USER}:$${DB_PASS}@$${DB_HOST}/$${DB_NAME}" > /opt/csye6225/db_properties.ini
    sudo chown csye6225:csye6225 /opt/csye6225/db_properties.ini
    sudo chmod 660 /opt/csye6225/db_properties.ini
  EOF
}


resource "google_compute_health_check" "webapp_health_check" {
  name               = "webapp-health-check"
  check_interval_sec = 30
  timeout_sec        = 10

  http_health_check {
    port         = 8080
    request_path = "/healthz"  
  }
}

resource "google_compute_region_instance_group_manager" "webapp_group_manager" {
  name = "webapp-instance-group-manager"

  base_instance_name = "webapp"
  region             = var.region
  version {
    instance_template = google_compute_instance_template.webapp_template.self_link
    name = "v1"
  }

  named_port {
    name = "http"
    port = 8080
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.webapp_health_check.id
    initial_delay_sec = 300
  }



}

resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  name   = "webapp-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.webapp_group_manager.self_link
  
  autoscaling_policy {
    max_replicas    = 6
    min_replicas    = 3
    cooldown_period = 60
    cpu_utilization {
      target = 0.05
    }
  }
}


resource "google_compute_managed_ssl_certificate" "webapp_ssl_cert" {
  name    = "webapp-ssl-cert"
  managed {
    domains = ["bharathbhaskar.me"]
  }
}

resource "google_compute_url_map" "webapp_url_map" {
  name            = "webapp-url-map"
  default_service = google_compute_backend_service.webapp_backend.self_link
}

resource "google_compute_target_https_proxy" "webapp_https_proxy" {
  name             = "webapp-https-proxy"
  url_map          = google_compute_url_map.webapp_url_map.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.webapp_ssl_cert.self_link]
}

resource "google_compute_global_forwarding_rule" "webapp_https_forwarding_rule" {
  name       = "webapp-https-forwarding-rule"
  target     = google_compute_target_https_proxy.webapp_https_proxy.self_link
  port_range = "443"
}

resource "google_dns_record_set" "webapp_dns" {
  name         = var.domain_name
  type         = "A"
  ttl          = 300
  managed_zone = var.dns_managed_zone
  rrdatas      = [google_compute_global_forwarding_rule.webapp_https_forwarding_rule.ip_address]
}


resource "google_compute_backend_service" "webapp_backend" {
  name        = "webapp-backend-service"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 10


  health_checks = [google_compute_health_check.webapp_health_check.self_link]

  backend {
    group = google_compute_region_instance_group_manager.webapp_group_manager.instance_group
  }

  // Enable Cloud CDN (optional)
  enable_cdn = false
}

#Service Account
resource "google_service_account" "webapp_service_acc" {
  account_id   = "webapp-service-acc"
  display_name = "VM Service Account"
}

#Bind IAM roles to the Service Account
resource "google_project_iam_binding" "logging_admin_binding" {
  project = var.project_id
  role    = "roles/logging.admin"
  
  members = [
    "serviceAccount:${google_service_account.webapp_service_acc.email}"
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer_binding" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  
  members = [
    "serviceAccount:${google_service_account.webapp_service_acc.email}"
  ]
}

resource "google_project_iam_binding" "pubsub_publisher_binding" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  
  members = [
    "serviceAccount:${google_service_account.webapp_service_acc.email}"
  ]
}

resource "google_storage_bucket" "cloud_functions_bucket" {
  name     = "cloud-functionz-buckets"
  location = var.region

  depends_on = [
    google_kms_crypto_key_iam_binding.storage_encryption_key_iam_binding
  ]
}

resource "google_cloudfunctions_function" "verify_email_function" {
  name        = "verify-email"
  description = "Sends verification emails to new users"
  runtime     = "python39"

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.cloud_functions_bucket.name
  source_archive_object = google_storage_bucket_object.function_archive.name
  entry_point = "send_verification_email"

  environment_variables = {
    MAILGUN_DOMAIN = "bharathbhaskar.me"
    MAILGUN_API_KEY = "3aa5b7aec14341f5adb31b70619144ff-f68a26c9-44c6d1a4"
  }

  service_account_email = google_service_account.cloud_function_service_acc.email

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource = google_pubsub_topic.verify_email_topic.id
    failure_policy {
      retry = false
    }
  } 
}


resource "google_storage_bucket_object" "function_archive" {
  name   = "verify-email-function.zip"
  bucket = google_storage_bucket.cloud_functions_bucket.name
  source = "./function.zip" # Adjust this to the path where your zipped function code is located
}


resource "google_pubsub_topic" "verify_email_topic" {
  name = "verify_email"
}

resource "google_service_account" "cloud_function_service_acc" {
  account_id   = "cloud-function-service-acc"
  display_name = "Cloud Function Service Account"
}

resource "google_pubsub_subscription" "verify_email_subscription" {
  name  = "verify-email-subscription"
  topic = google_pubsub_topic.verify_email_topic.name

  ack_deadline_seconds = 20
}

resource "google_kms_key_ring" "key_ring" {
  name     = "my-key-rings1"
  location = var.region  # Ensure this is the region where you are deploying your resources
  project  = var.project_id
}

resource "google_kms_crypto_key" "vm_encryption_key" {
  name            = "vm-encryption-key"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = "2592000s"  # 30 days in seconds

  lifecycle {
    prevent_destroy = false
  }

  purpose = "ENCRYPT_DECRYPT"
}

resource "google_kms_crypto_key" "cloudsql_encryption_key" {
  name            = "cloudsql-encryption-key"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = "2592000s"  # 30 days in seconds

  lifecycle {
    prevent_destroy = false
  }

  purpose = "ENCRYPT_DECRYPT"
}

resource "google_kms_crypto_key" "storage_encryption_key" {
  name            = "storage-encryption-key"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = "2592000s"  # 30 days in seconds

  lifecycle {
    prevent_destroy = false
  }

  purpose = "ENCRYPT_DECRYPT"
}



resource "google_project_service_identity" "cloudsql_sa" {
  provider = google-beta

  project = var.project_id
  service = "sqladmin.googleapis.com"
}

resource "google_project_service_identity" "cloudstorage_sa" {
  provider = google-beta

  project = var.project_id
  service = "storage.googleapis.com"
}


resource "google_kms_crypto_key_iam_binding" "cloudsql_crypto_key_iam_binding" {
  crypto_key_id = google_kms_crypto_key.cloudsql_encryption_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  members = [
    "serviceAccount:${google_project_service_identity.cloudsql_sa.email}"
  ]
}

resource "google_kms_crypto_key_iam_binding" "storage_encryption_key_iam_binding" {


  crypto_key_id = google_kms_crypto_key.storage_encryption_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  members = [
    "serviceAccount:${google_service_account.cloud_function_service_acc.email}"

  ]
}

resource "google_kms_crypto_key_iam_binding" "vm_crypto_key_iam_binding" {
  crypto_key_id = google_kms_crypto_key.vm_encryption_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  members = [
    "serviceAccount:${google_service_account.webapp_service_acc.email}"
  ]
}



