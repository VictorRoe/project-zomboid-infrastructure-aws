# Estado remoto en S3 con bloqueo nativo (archivo .tflock). El bucket y la región
# van en backend.hcl (ignorado por git; ver backend.hcl.example) y el bucket se crea
# aparte con bootstrap/state-backend. Los tests usan `init -backend=false`.
terraform {
  backend "s3" {
    key          = "project-zomboid/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
