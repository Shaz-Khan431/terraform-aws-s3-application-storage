terraform {
  # v1.5.x is the last MPL licensed release before Hashicorp moved to the BSL license in v1.6
  # Some companies stayed on v1.5.x, keeping this module usable for them
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # v6 is what CI tests against
      # Hashicorp wants minimum only, so consumers can adopt without new module releases
      version = ">= 6.0"
    }
  }
}

