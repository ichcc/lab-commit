resource "random_password" "admin" {
  length      = 20
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

resource "aws_ssm_parameter" "admin_password" {
  name  = "/${var.project}/windows-admin-password"
  type  = "SecureString"
  value = random_password.admin.result
}

resource "aws_ssm_document" "setup" {
  name            = "${var.project}-windows-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Set the Administrator password, trust the lab CA and install Chrome from S3"
    parameters = {
      Bucket = { type = "String" }
      Key    = { type = "String", default = var.chrome_key }
    }
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "setAdminPassword"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "$value = (Get-SSMParameter -Name '${aws_ssm_parameter.admin_password.name}' -WithDecryption $true -Region '${var.region}').Value",
            "Set-LocalUser -Name Administrator -Password (ConvertTo-SecureString $value -AsPlainText -Force)",
            "Enable-LocalUser -Name Administrator",
            "Write-Output 'Administrator password set'",
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "trustLabCertificate"
        inputs = {
          runCommand = [file("${path.module}/../../scripts/trust-cert.ps1")]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "installChrome"
        inputs = {
          timeoutSeconds = "1200"
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "if (Test-Path 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe') { Write-Output 'Chrome already installed'; exit 0 }",
            "$msi = Join-Path $env:TEMP 'chrome.msi'",
            "Read-S3Object -BucketName '{{ Bucket }}' -Key '{{ Key }}' -File $msi -Region '${var.region}' | Out-Null",
            "$process = Start-Process -FilePath msiexec.exe -ArgumentList \"/i `\"$msi`\" /qn /norestart\" -Wait -PassThru",
            "Remove-Item -Path $msi -Force",
            "if ($process.ExitCode -ne 0) { throw \"msiexec exit code $($process.ExitCode)\" }",
            "Write-Output 'Chrome installed'",
          ]
        }
      },
    ]
  })
}

resource "aws_ssm_association" "setup" {
  name             = aws_ssm_document.setup.name
  association_name = "${var.project}-windows-setup"

  parameters = {
    Bucket = aws_s3_bucket.installers.id
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows.id]
  }
}
