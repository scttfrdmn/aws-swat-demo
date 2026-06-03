#!/usr/bin/env Rscript
# 01-setup.R — One-time: configure staRburst and stage the SWAT model to S3.
#
# Prereqs: AWS creds; the SWAT+ worker base image pushed (docker/build-and-push.sh);
# a SWAT+ TxtInOut model in data-raw/model/ (see data-raw/fetch-sample-model.sh).

suppressMessages(library(starburst))

region <- Sys.getenv("AWS_REGION", "us-east-1")

# Provision AWS resources. build_image = FALSE keeps setup fast — the worker
# image is our custom SWAT+ base, built separately by docker/build-and-push.sh.
# (build_image was added to starburst in issue #30.)
starburst_setup(region = region, force = TRUE, use_public_base = FALSE,
                build_image = FALSE)

cfg <- starburst:::get_starburst_config()
bucket <- cfg$bucket
message("staRburst bucket: ", bucket)

# Stage the SWAT model tree to S3 as a tarball (GAP B: file staging is manual).
model_dir <- "data-raw/model"
if (!dir.exists(model_dir) || !length(list.files(model_dir))) {
  stop("No SWAT model in ", model_dir, " — run data-raw/fetch-sample-model.sh first.")
}
tarball <- file.path(tempdir(), "swat-model.tar.gz")
old <- setwd(model_dir); utils::tar(tarball, ".", compression = "gzip"); setwd(old)

key <- "swat-demo/model.tar.gz"
s3 <- paws.storage::s3(config = list(region = region))
s3$put_object(Bucket = bucket, Key = key, Body = tarball)

message("Model staged: s3://", bucket, "/", key)
writeLines(sprintf("s3://%s/%s", bucket, key), "data-raw/model_s3_uri.txt")
message("Wrote data-raw/model_s3_uri.txt — used by scripts/03-run-ensemble-aws.R")
