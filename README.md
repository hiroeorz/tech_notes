# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Cloudflare R2 image storage

This application stores uploaded images with Active Storage on Cloudflare R2.
Article images are inserted into Markdown as public CDN URLs.

Required environment variables:

```bash
export CLOUDFLARE_R2_ACCESS_KEY_ID="..."
export CLOUDFLARE_R2_SECRET_ACCESS_KEY="..."
export CLOUDFLARE_R2_BUCKET="your-bucket-name"
export CLOUDFLARE_R2_ENDPOINT="https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
export ACTIVE_STORAGE_PUBLIC_BASE_URL="https://cdn.example.com"
```

### Bucket name

Use the existing R2 bucket name for `CLOUDFLARE_R2_BUCKET`.

In Cloudflare Dashboard:

1. Open `R2 Object Storage`.
2. Open `Buckets`.
3. Copy the bucket name.

### Access key and secret

Create an R2 API token for `CLOUDFLARE_R2_ACCESS_KEY_ID` and
`CLOUDFLARE_R2_SECRET_ACCESS_KEY`.

In Cloudflare Dashboard:

1. Open `R2 Object Storage`.
2. Open the API token management screen from the R2 account details area.
3. Create an account or user API token.
4. Grant object read/write access to the target bucket.
5. Copy the generated `Access Key ID` and `Secret Access Key`.

The secret access key is shown only when the token is created. Store it
immediately.

### R2 endpoint

Set `CLOUDFLARE_R2_ENDPOINT` from the Cloudflare account ID.

```bash
export CLOUDFLARE_R2_ENDPOINT="https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
```

For an EU jurisdiction bucket, use:

```bash
export CLOUDFLARE_R2_ENDPOINT="https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com"
```

The account ID is available in the Cloudflare Dashboard account overview.

### Public CDN URL

Set `ACTIVE_STORAGE_PUBLIC_BASE_URL` to the public CDN URL used for R2 object
delivery. A custom domain on the R2 bucket is recommended.

In Cloudflare Dashboard:

1. Open `R2 Object Storage`.
2. Open the target bucket.
3. Open `Settings`.
4. Add a domain under `Custom Domains`.
5. Wait until the domain status becomes active.

Then set:

```bash
export ACTIVE_STORAGE_PUBLIC_BASE_URL="https://cdn.example.com"
```

The CDN URL must serve objects by their Active Storage blob key. For example,
if the blob key is `abc123`, this URL must return the image:

```text
https://cdn.example.com/abc123
```

### Kamal deployment

`config/deploy.yml` expects these values as secrets:

- `CLOUDFLARE_R2_ACCESS_KEY_ID`
- `CLOUDFLARE_R2_SECRET_ACCESS_KEY`
- `CLOUDFLARE_R2_BUCKET`
- `CLOUDFLARE_R2_ENDPOINT`
- `ACTIVE_STORAGE_PUBLIC_BASE_URL`

Set them in the shell or secret manager used by `.kamal/secrets` before running
`kamal deploy`.
