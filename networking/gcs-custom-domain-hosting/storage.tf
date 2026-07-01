locals {
  # Generate bucket name if not explicitly provided
  actual_bucket_name = var.bucket_name != "" ? var.bucket_name : replace(var.domain_name, ".", "-")
}

# 1. Google Cloud Storage Bucket for Static Website Hosting
resource "google_storage_bucket" "website" {
  name          = local.actual_bucket_name
  location      = "US" # US multi-region recommended for Global Load Balancer backend
  force_destroy = false

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  uniform_bucket_level_access = true
}

# 2. Make Bucket Objects Publicly Readable (for static web hosting)
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.website.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# 3. Automatically Upload Website Content Files to Bucket
resource "google_storage_bucket_object" "content" {
  for_each = fileset("${path.module}/website_content", "**/*")

  name   = each.value
  bucket = google_storage_bucket.website.name
  source = "${path.module}/website_content/${each.value}"

  # Automatically set Content-Type for proper browser rendering
  content_type = lookup({
    "html" = "text/html; charset=utf-8",
    "css"  = "text/css; charset=utf-8",
    "js"   = "application/javascript; charset=utf-8",
    "png"  = "image/png",
    "jpg"  = "image/jpeg",
    "svg"  = "image/svg+xml",
    "json" = "application/json"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "text/plain")
}

