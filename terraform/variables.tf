#defining variables
variable "project_id" {
  type    = string
  description = "The Google Cloud project ID."
  default = "dev6225webapp"
}

variable "vpc_name" {
  description = "The name of the VPC network"
  type        = list(string)
  default     = ["cloud-vpc2"]
}

variable "zone"{
  description = "The name of the zone"
  type        = string
  default     = "us-west4-b"
}

variable "routing_mode"{
  description = "The type of routing mode"
  type        = string
  default     = "REGIONAL"
}
 
variable "webapp_subnet_cidr" {
  description = "The IP CIDR range for the webapp subnet"
  type        = string
  default     = "10.1.0.0/24"
}

variable "db_subnet_cidr" {
  description = "The IP CIDR range for the db subnet"
  type        = string
  default     = "10.3.0.0/24"
}

variable "machine_type" {
  description = "The machine type"
  type        = string
  default     = "e2-medium" 
}

variable "db_disk_type"{
  description = "The disk type"
  type        = string
  default     = "PD-SSD"
}

variable "db_disk_size"{
  description = "The disk size"
  type        = number
  default     = 100
}

variable "custom_image" {
  description = "The custom image for the boot disk of the compute instance"
  type        = string
  default     = "centos-8-image-20240408195431" //centos-8-image-20240403190418
}

variable "webapp_reserve_address" {
  description = "The reserve global internal IP address for Private Service Connect "
  type        = string
  default     = "10.0.1.0"
}

variable "region" {
  description = "Region"
  type        =  string
  default     = "us-west4"
}

variable "dns_managed_zone" {
  description = "DNS managed zone"
  type        =  string
  default     = "bharath-bhaskar-name"
}

variable "domain_name" {
  description = "DNS domain name"
  type        =  string
  default     = "bharathbhaskar.me."
}

variable "mailgun_api_key"{
  description = "Mailgun API Key"
  type        = string
  default     = "3aa5b7aec14341f5adb31b70619144ff-f68a26c9-44c6d1a4"
}
variable "sql_database_name" {
  description = "Sql Database Name"
  type        =  string
  default     = "Users"
}
