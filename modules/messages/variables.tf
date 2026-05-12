variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "visibility_timeout" {
  type    = number
  default = 90
}

variable "max_receive_count" {
  type    = number
  default = 3
}
