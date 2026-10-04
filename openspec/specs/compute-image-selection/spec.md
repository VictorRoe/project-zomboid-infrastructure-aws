# compute-image-selection Specification

## Purpose
Defines how the Project Zomboid server's machine image is selected so the stack deploys in any AWS region without editing code.

## Requirements

### Requirement: Region-resolved default image
When no image override is supplied, the stack SHALL use the most recent Canonical Ubuntu Server LTS x86_64 (hvm, gp3/ebs) image available in the configured `aws_region`.

#### Scenario: Default lookup
- **WHEN** the stack is planned with no `ami_id` and the Ubuntu image lookup returns `ami-lookup123`
- **THEN** the instance uses `ami-lookup123`

### Requirement: Explicit image override
The stack SHALL accept an optional `ami_id` input; when it is non-empty and no world restore applies, the instance SHALL use exactly that image and the lookup result SHALL be ignored.

#### Scenario: Override supplied
- **WHEN** the stack is planned with `ami_id = "ami-override123"`
- **THEN** the instance's image is `ami-override123`

### Requirement: Offline verification
The image-selection behavior SHALL be verifiable with mocked providers, requiring no AWS credentials or network calls to AWS APIs.

#### Scenario: Tests run without credentials
- **WHEN** `make test` runs with no AWS credentials configured
- **THEN** the image-selection tests execute and pass

### Requirement: No implicit replacement on image change
A change in the resolved image SHALL NOT replace an existing server instance; replacement SHALL happen only when explicitly requested.

#### Scenario: Newer image published
- **WHEN** the instance exists and the lookup later resolves a different image ID
- **THEN** the plan shows no replacement of the instance

### Requirement: Region-consistent placement
The availability zone SHALL default to one chosen by AWS within `aws_region`, and an explicitly set zone outside that region SHALL be rejected at plan time.

#### Scenario: Mismatched zone
- **WHEN** `aws_region = "sa-east-1"` and `availability_zone = "us-east-1a"`
- **THEN** planning fails with a validation error
