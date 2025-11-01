# 🚀 Deploy Java Application on AWS EC2 using Terraform

This Terraform script launches an EC2 instance, installs Java, downloads your `.jar` file from S3, and runs it automatically as a background service. Everything happens in one go.

---

## 🧰 Requirements

Before running Terraform, make sure you have:

1. **Terraform** installed  
   Verify:
   ```bash
   terraform -version
   ```

2. **AWS CLI** installed and configured  
   Run:
   ```bash
   aws configure
   ```
   Provide your AWS Access Key, Secret Key, region, and output format.

3. **An existing EC2 key pair**  
   You’ll need a `.pem` file to SSH into the instance later.  
   You can create one from the AWS Console → EC2 → Key Pairs.

4. **Your Java `.jar` file uploaded to S3**  
   Example:
   ```bash
   aws s3 cp myapp.jar s3://my-bucket/app/myapp.jar
   ```

---

## ⚙️ Configuration

Open the file `ec2_java_deploy.tf` and set these variables:

```hcl
key_name      = "your-ec2-keypair"      # existing EC2 key pair name
bucket_name   = "your-s3-bucket-name"   # where JAR is stored
jar_key       = "path/to/myapp.jar"     # key (path) to your JAR inside S3
allow_ssh_from = "YOUR.IP.ADDRESS/32"   # your public IP for SSH access
```

You can also change:
- `aws_region` (default: `us-east-1`)
- `instance_type` (default: `t3.micro`)

---

## 🪄 Deployment Steps

### Step 1: Initialize Terraform
Download required providers and set up the working directory.
```bash
terraform init
```

### Step 2: Preview the Plan
See what Terraform will build (optional but wise).
```bash
terraform plan
```

### Step 3: Apply and Deploy
Actually launch everything on AWS.
```bash
terraform apply -auto-approve
```

Terraform will:
- Create a VPC, subnet, and security group  
- Launch an EC2 instance  
- Install Java 11 and AWS CLI  
- Download your `.jar` from S3  
- Start it as a systemd service  

---

## 🖥️ Access the Instance

After deployment, Terraform prints output like:
```
instance_ip  = 3.91.xxx.xxx
instance_dns = ec2-3-91-xxx-xxx.compute.amazonaws.com
```

SSH into it:
```bash
ssh -i your-key.pem ec2-user@<instance_ip>
```

Check if your Java app is running:
```bash
sudo systemctl status java-app
```

View logs:
```bash
sudo journalctl -u java-app -f
```

---

## 🧹 Destroy Everything

When you’re done (or AWS bills start to sting), clean up:
```bash
terraform destroy -auto-approve
```

---

## 💡 Notes
- Default security group opens **port 22 (SSH)** and **port 80 (HTTP)**.  
  Tighten this for production.  
- Java version: **OpenJDK 11**
- Your app will auto-start on reboot (`systemd` enabled).
- If you push a new `.jar` to S3, SSH in and restart the service:
  ```bash
  sudo systemctl restart java-app
  ```

---

That’s it. One command (`terraform apply`) and your Java app will be up and running on AWS EC2.
