variable "region" {
  default = "us-east-1"
}

variable "transcode-bucket-name" {
  default = "mac3-sfb-transcoded"
}

variable "ownername" {
  default = "mac3"
}

variable "upload-bucket-name" {
  default = "mac3-sfb-upload"
}

variable "job_submitter_name" {
  default = "mac-lambda-et-job-submitter"
}
