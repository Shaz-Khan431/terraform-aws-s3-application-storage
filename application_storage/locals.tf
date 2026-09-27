locals {
  # tagging standards in one place where the caller cannot override the values
  standard_tags = {
    Application        = var.application
    Environment        = var.environment
    Purpose            = var.purpose
    DataClassification = var.data_classification
    ManagedBy          = "terraform"
    Module             = "application_storage"
  }

  # standard_tags is mentioned last to ensure that they cannot be overwritten by duplicate entries in var.tags
  tags = merge(var.tags, local.standard_tags)
}
